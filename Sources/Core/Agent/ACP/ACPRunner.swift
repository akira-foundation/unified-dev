import Foundation
import Synchronization
import os

public actor ACPRunner: SessionRunner {
    public nonisolated let dialect: ACPDialect
    public nonisolated var agentKind: AgentKind { dialect.kind }
    public nonisolated let workspacePath: String
    public nonisolated let sessionID: SessionID

    private let store: Store
    private let makeClient: @Sendable (ACPClient.Configuration) -> ACPClient

    private var session: Session
    private var client: ACPClient?
    private var pumpTask: Task<Void, Never>?
    private var translation: ACPTranslation
    private var acpSessionID: String?
    private var connectionGeneration: UInt64 = 0
    private var permissionConnectionID = UUID()
    private var launchedAlwaysApproving = false

    private let grants: SessionGrants
    private var orchestrates = false
    private var announcesRole = false
    private let segment: RunnerSegment
    private var lastContextWindow: Int?
    private var wireModel: String { ModelIdentifier.resolve(session.model).model }

    private var approvals: [String: ACPPermissionRequest] = [:]

    private let connection = LiveConnection()
    private var droppingConnections = 0
    private let pending = PendingAsks()
    private let handle = CodexTurnHandle()
    private let sink = AgentPresentationFeed()
    private let announced = StoredMessageRelay()
    private var sendsInFlight = 0
    private var wasEvicted = false
    private var trouble = PersistenceTrouble()
    private let bridge: BridgeAttachment?
    private let account: AgentAccountHome?
    private let gitHub: GitHubLogin

    public init(
        dialect: ACPDialect,
        workspacePath: String,
        session: Session,
        store: Store,
        segmentID: SessionSegmentID,
        bridge: BridgeAttachment? = nil,
        account: AgentAccountHome? = nil,
        gitHub: GitHubLogin = .thisMac,
        makeClient: @escaping @Sendable (ACPClient.Configuration) -> ACPClient = ACPRunner.spawn
    ) {
        self.dialect = dialect
        self.workspacePath = workspacePath
        self.sessionID = session.id
        self.session = session
        self.store = store
        self.bridge = bridge
        self.account = account
        self.gitHub = gitHub
        self.segment = RunnerSegment(sessionID: session.id, store: store, id: segmentID)
        self.makeClient = makeClient
        self.grants = SessionGrants(store: store, workspaceID: session.workspaceID)
        self.translation = ACPTranslation(context: ACPTranslation.Context(
            agentKind: dialect.kind,
            model: ModelIdentifier.resolve(session.model).model,
            cwd: workspacePath,
            permissionMode: session.permissionMode.cliValue
        ))
    }

    public static let spawn: @Sendable (ACPClient.Configuration) -> ACPClient = { configuration in
        ACPClient(configuration: configuration)
    }

    public nonisolated var events: AsyncStream<AgentEvent> { sink.stream() }
    public nonisolated var presentationFeed: AgentPresentationFeed? { sink }
    public nonisolated var storedMessages: StoredMessageRelay? { announced }

    public var isProcessAlive: Bool { connection.current?.isProcessAlive ?? false }

    public var hasStoppedWriting: Bool { client == nil && droppingConnections == 0 }

    public var currentSession: Session { session }

    public var lastPersistenceFailure: String? { trouble.lastSentence }

    public var persistenceFailureCount: Int { trouble.failures }

    static let clientVersion = "1.0"

    public func send(_ text: String, recording: Data? = nil) async throws {
        try await send(text, recording: recording, deliveryID: nil, deliveredSeq: nil, interactionMode: nil)
    }

    public func evictIfIdle(for duration: Duration) async -> Bool {
        guard !wasEvicted, sendsInFlight == 0, !session.state.isMidTurn,
              session.agentSessionID != nil, pending.isEmpty, !sink.hasBackgroundWork else { return false }
        let lastActivity = sink.lastActivity
        guard lastActivity.duration(to: .now) >= duration,
              let waiting = try? await store.pendingDeliveries(sessionID: session.id), waiting.isEmpty else { return false }
        guard sendsInFlight == 0, !session.state.isMidTurn, pending.isEmpty,
              !sink.hasBackgroundWork, sink.lastActivity == lastActivity else { return false }
        wasEvicted = true
        terminateNow()
        return true
    }

    public func sendDelivery(_ delivery: Delivery) async throws {
        try await send(delivery.sent, recording: delivery.crewPayload, deliveryID: delivery.id,
                       deliveredSeq: try await store.delivery(id: delivery.id)?.deliveredSeq,
                       interactionMode: delivery.interactionMode)
    }

    private func send(_ text: String, recording: Data?, deliveryID: DeliveryID?, deliveredSeq: Int?,
                      interactionMode: InteractionMode?) async throws {
        guard !wasEvicted else { throw ProviderIdleError.retired }
        sendsInFlight += 1
        sink.noteActivity()
        defer { sendsInFlight -= 1 }
        try await segment.refuseIfRetired { self.terminateNow() }
        let generation = handle.generation
        let replacement = handle.prepareReplacement()
        defer { handle.finishReplacement(replacement) }
        try handle.check(generation)
        if handle.wasCancelled {
            for event in translation.finishInterruptedTurn() { await emit(event) }
            try handle.check(generation)
        }
        let sidePrompt = try await store.sideConversationTurn(text, sessionID: sessionID)
        orchestrates = await grants.isOrchestrator()
        let client = try await connected()
        try handle.check(generation)
        let acpSessionID = try await openSession(on: client)
        try handle.check(generation)
        try await applyComposerSettings(on: client, sessionID: acpSessionID)
        try handle.check(generation)

        await segment.confirmWhatIsOwed()
        let prompt = try await store.handoffPrompt(
            sidePrompt, session: session, deliveredSeq: deliveredSeq,
            workspacePath: workspacePath, contextWindow: lastContextWindow
        )
        try handle.check(generation)

        if deliveryID == nil {
            if let recording { await persist(kind: .crew, payload: recording) } else { await persist(kind: .user, payload: Self.userPayload(text)) }
        }
        try handle.check(generation)

        if let deliveryID { try await store.beginDeliveryDispatch(id: deliveryID) }
        let spoken = SessionRolePrompt.text(
            prompt, workspaceID: session.workspaceID, orchestrates: orchestrates, opensSession: announcesRole
        )
        announcesRole = false
        segment.promptSent(asSteer: false, carriedDelta: prompt != sidePrompt)
        let promptID = try await client.beginPrompt(sessionID: acpSessionID, text: spoken)
        if let deliveryID { try await store.acceptDelivery(id: deliveryID, providerTurnID: promptID.turnID) }
        guard handle.begin(turnID: promptID.turnID, generation: generation) else {
            await client.cancel(sessionID: acpSessionID)
            throw CancellationError()
        }

        session.apply(.turnStarted)
        await save(session)
        if sidePrompt != text {
            try? await store.acknowledgeSideConversationContext(sessionID: sessionID)
        }
    }

    public nonisolated func cancelNow() {
        let stopped = handle.markCancelled()
        Task { await self.stopTurn(stopped) }
    }

    private func stopTurn(_ stopped: CodexTurnHandle.Stopped) async {
        if handle.generation == stopped.generation, handle.wasCancelled {
            for event in translation.finishInterruptedTurn() { await emit(event) }
            await filePendingAsks()
        }
        if handle.generation == stopped.generation, handle.wasCancelled,
           session.apply(.cancelled).moves { await save(session) }
        if handle.generation == stopped.generation, handle.wasCancelled, let acpSessionID {
            await client?.cancel(sessionID: acpSessionID)
        }
    }

    public nonisolated func terminateNow() {
        sink.noteProcessEnded()
        handle.markCancelled()
        connection.current?.terminateNow()
        Task { await self.shutdown() }
    }

    public func answer(requestID: String, decision: PermissionDecision) async {
        guard let ask = pending.take(requestID) else { return }
        let request = approvals[requestID]
        await write(answerTo: ask, decision: decision, request: request)
        await close(ask, as: decision.storedName, note: "", answers: decision.answers)
        await grants.record(decision, from: ask)
    }

    public func shutdown() async {
        await filePendingAsks()
        if session.apply(.cancelled).moves { await save(session) }
        await dropConnection()
    }

    private func dropConnection() async {
        droppingConnections += 1
        defer { droppingConnections -= 1 }
        connectionGeneration += 1
        let closing = client
        let sessionToClose = acpSessionID
        let pump = pumpTask
        client = nil
        acpSessionID = nil
        pumpTask?.cancel()
        pumpTask = nil
        handle.end()
        approvals.removeAll()
        for event in translation.finishInterruptedTurn() { await emit(event) }
        if let sessionToClose {
            await closing?.closeSession(sessionToClose)
        }
        await closing?.stop()
        await pump?.value
    }

    private func connected() async throws -> ACPClient {
        let alwaysApproves = permissionMode == .bypassPermissions
        if let client {
            if client.isProcessAlive, await client.isClosed == false, launchedAlwaysApproving == alwaysApproves {
                return client
            }
            await dropConnection()
        }

        await LoginShellPath.ready()
        let stored = try? await store.setting(AgentCatalog.executablePathSettingKey(dialect.kind))
        let client = makeClient(ACPClient.Configuration(
            dialect: dialect,
            executable: AgentCatalog.executable(for: dialect.kind, override: stored),
            cwd: workspacePath,
            account: account,
            clientName: "Unified Dev",
            clientVersion: Self.clientVersion,
            environment: gitHub.applied(to: Shell.environment()),
            model: wireModel,
            effort: session.effort,
            alwaysApprove: alwaysApproves,
            asksEveryCall: orchestrates
        ))
        self.client = client
        launchedAlwaysApproving = alwaysApproves
        permissionConnectionID = UUID()
        connection.attach(client)
        let events = client.events
        let generation = connectionGeneration
        pumpTask = Task { [weak self] in
            for await event in events {
                await self?.handle(event, from: generation)
            }
        }
        try await client.start()
        return client
    }

    private func openSession(on client: ACPClient) async throws -> String {
        if let acpSessionID { return acpSessionID }

        announcesRole = true
        let servers = BridgeRegistration.acpServers(bridge)
        let stored = session.agentSessionID ?? ""
        let opened: ACPSession
        if stored.isEmpty {
            opened = try await client.newSession(
                cwd: workspacePath,
                mcpServers: servers,
                permissionMode: permissionMode
            )
        } else {
            do {
                opened = try await client.resumeSession(
                    stored,
                    cwd: workspacePath,
                    mcpServers: servers,
                    permissionMode: permissionMode
                )
            } catch {
                opened = try await client.newSession(
                    cwd: workspacePath,
                    mcpServers: servers,
                    permissionMode: permissionMode
                )
            }
        }
        if SegmentResume.lostHistory(requested: stored, received: opened.id) {
            try await segment.restartHistory()
        }

        acpSessionID = opened.id
        translation.context.permissionMode = permissionMode.cliValue
        for event in translation.translate(.sessionReady(opened)) {
            await emit(event)
        }
        if session.agentSessionID != opened.id {
            session = session.with {
                $0.agentSessionID = opened.id
                $0.updatedAt = Date()
            }
            await save(session)
        }
        return opened.id
    }

    private var permissionMode: PermissionMode {
        OrchestratorToolGuard.permissionMode(session.permissionMode, orchestrates: orchestrates)
    }

    private func applyComposerSettings(on client: ACPClient, sessionID: String) async throws {
        let model = wireModel
        if !model.isEmpty {
            try await applyConfigOption(on: client, sessionID: sessionID, configID: "model", value: model)
            translation.context.model = model
        }
        if let effortOption = dialect.effortOption, !session.effort.isEmpty {
            try await applyConfigOption(on: client, sessionID: sessionID, configID: effortOption, value: session.effort)
        }
        if let mode = dialect.mode(for: permissionMode, asksEveryCall: orchestrates) {
            try await applyConfigOption(
                on: client, sessionID: sessionID, configID: "mode", value: mode, isRequired: orchestrates
            )
        }
    }

    private func applyConfigOption(
        on client: ACPClient,
        sessionID: String,
        configID: String,
        value: String,
        isRequired: Bool = false
    ) async throws {
        do {
            try await client.setConfigOption(sessionID: sessionID, configID: configID, value: value)
        } catch let error as ACPClientError {
            switch error {
            case .connectionClosed, .notInitialized: throw error
            case .timedOut, .unexpectedResult: if isRequired { throw error }
            }
        } catch {
            if isRequired { throw error }
        }
    }

    private func handle(_ event: ACPEvent, from generation: UInt64) async {
        guard generation == connectionGeneration else { return }

        if case .closed = event, handle.wasCancelled || trouble.hasStopped { return }

        if case .permission(let request) = event {
            if handle.wasCancelled {
                await client?.answer(request.id, with: ACPPermission.cancelledResult)
                return
            }
            await ask(request)
            return
        }

        if case .update = event, handle.wasCancelled { return }

        let ending = if case .promptCompleted(let result) = event { result.requestID.turnID } else { nil as String? }
        if let ending, !handle.acceptsTerminal(turnID: ending) { return }

        for translated in translation.translate(event) {
            await emit(translated, endingTurn: ending)
        }
    }

    private func emit(_ event: AgentEvent, endingTurn: String? = nil) async {
        let intent = handle.intent
        var storedMessage: Message?
        if event.isTranscriptRow {
            storedMessage = await persist(
                kind: event.kind,
                payload: event.raw.isEmpty ? Data("{}".utf8) : event.raw,
                refID: event.refID
            )
        }

        if let endingTurn, !handle.acceptsTerminal(turnID: endingTurn, intent: intent) { return }

        if segment.takeReply(event) { await segment.confirm(carriedDelta: true) }

        switch event {
        case .result(let result):
            handle.end()
            let owed = segment.takeTurnEnd()
            if result.usage.contextTokens > 0 { lastContextWindow = result.usage.contextTokens }
            session.apply(.turnFinished(isError: result.isError))
            session = session.with {
                $0.inputTokens += result.usage.inputTokens
                $0.outputTokens += result.usage.outputTokens
                if result.usage.contextTokens > 0 { $0.contextTokens = result.usage.contextTokens }
            }
            await save(session)
            if owed { await segment.confirm(carriedDelta: false) }

        case .error:
            handle.end()
            let owed = segment.takeTurnEnd()
            session.apply(.turnFinished(isError: true))
            await save(session)
            if owed { await segment.confirm(carriedDelta: false) }

        default:
            break
        }

        if let endingTurn, !handle.acceptsTerminal(turnID: endingTurn, intent: intent) { return }
        if let storedMessage { announced.deposit(storedMessage) }
        sink.yield(event, messageSeq: storedMessage?.seq)
    }

    private func ask(_ request: ACPPermissionRequest) async {
        let ask = ACPPermission.ask(for: request, kind: dialect.kind, connectionID: permissionConnectionID)
        if await grants.answersItself(toolName: ask.toolName, input: ask.input) {
            await persist(kind: .system, payload: ask.raw)
            await write(answerTo: ask, decision: .allow(scope: .once), request: request)
            return
        }
        pending.add(ask)
        approvals[ask.requestID] = request

        do {
            try await store.appendPermissionAsk(sessionID: session.id, ask: ask)
        } catch {
            await report("could not store a permission question", error)
        }
        await persist(kind: .permissionAsk, payload: ask.raw, refID: ask.toolUseID)
        sink.yield(.permissionAsk(ask))

        if let refusal = await grants.refusal(toolName: ask.toolName, input: ask.input),
           let claimed = pending.take(ask.requestID) {
            let decision = PermissionDecision.deny(message: refusal, endsTurn: false)
            await write(answerTo: claimed, decision: decision, request: request)
            await close(claimed, as: decision.storedName, note: refusal)
            return
        }

        let matched = await grants.matching(ask)
        if let matched, let claimed = pending.take(ask.requestID) {
            await write(answerTo: claimed, decision: .allow(scope: .session), request: request)
            await close(claimed, as: PermissionAskOutcome.auto, note: PermissionGrantIndex.note(for: matched))
            await grants.recordUse(of: matched)
            return
        }

        guard matched == nil, pending.contains(ask.requestID) else { return }
        session.apply(.blocked)
        await save(session)
    }

    private func filePendingAsks() async {
        for ask in pending.drain() {
            if let request = approvals[ask.requestID] {
                await client?.answer(request.id, with: ACPPermission.cancelledResult)
            }
            await close(ask, as: PermissionAskOutcome.stopped, note: "")
        }
        if session.apply(.unblocked).moves { await save(session) }
    }

    private func write(
        answerTo ask: PermissionAsk,
        decision: PermissionDecision,
        request: ACPPermissionRequest?
    ) async {
        if let request {
            if let optionID = ACPPermission.optionID(for: decision, in: request) {
                await client?.answer(request.id, with: ACPPermission.selectedResult(optionID: optionID))
            } else {
                await client?.answer(request.id, with: ACPPermission.cancelledResult)
            }
        }
        approvals[ask.requestID] = nil
        guard pending.isEmpty else { return }
        guard session.apply(.unblocked).moves else { return }
        await save(session)
    }

    private func close(
        _ ask: PermissionAsk, as decision: String, note: String, answers: [String: String] = [:]
    ) async {
        pending.remove(ask.requestID)
        approvals[ask.requestID] = nil
        do {
            try await store.resolvePermissionAsk(
                id: ask.requestID, decision: decision, answers: answers
            )
        } catch {
            await report("could not record a permission decision", error)
        }
        sink.yield(.permissionDecided(PermissionResolution(
            requestID: ask.requestID,
            toolUseID: ask.toolUseID,
            decision: decision,
            note: note,
            answers: answers
        )))
    }

    static func userPayload(_ text: String) -> Data {
        let json = JSONValue.object([
            "type": .string("user"),
            "message": .object([
                "role": .string("user"),
                "content": .array([.object([
                    "type": .string("text"),
                    "text": .string(text),
                ])]),
            ]),
        ])
        return Data(json.compactJSON.utf8)
    }

    @discardableResult
    private func persist(kind: MessageKind, payload: Data, refID: String? = nil) async -> Message? {
        do {
            return try await store.appendNext(
                sessionID: session.id,
                kind: kind,
                payload: payload,
                refID: refID
            )
        } catch {
            await report("could not store a \(kind.rawValue) row", error)
            return nil
        }
    }

    private func save(_ session: Session) async {
        do {
            try await segment.write {
                $0.agentSessionID = session.agentSessionID
                $0.state = session.state
                $0.inputTokens = session.inputTokens
                $0.outputTokens = session.outputTokens
                $0.contextTokens = session.contextTokens
                $0.updatedAt = session.updatedAt
            }
        } catch {
            await report("could not save the session", error)
        }
    }

    private func report(_ what: String, _ error: Error) async {
        Self.log.error("\(what, privacy: .public): \(error.readableMessage, privacy: .public)")

        let standing = await TranscriptStanding.of(sessionID: session.id, in: store)
        switch trouble.record(WorkspaceTrouble.recording(
            transcript: standing, complaint: TranscriptStanding.complaint(about: error)
        )) {
        case .tell(let sentence):
            sink.yield(.error(.storage(message: sentence)))
        case .stop:
            Self.log.info("the transcript for \(self.session.id.rawValue, privacy: .public) has been removed, so this run is being stopped without a word")
            terminateNow()
        case .alreadyStopped:
            break
        }
    }

    var transcriptWasRemoved: Bool { trouble.hasStopped }

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.akira.unifieddev",
        category: "acp-runner"
    )
}

private final class LiveConnection: Sendable {
    private let client = Mutex<ACPClient?>(nil)

    var current: ACPClient? { client.withLock { $0 } }

    func attach(_ client: ACPClient) {
        self.client.withLock { $0 = client }
    }
}

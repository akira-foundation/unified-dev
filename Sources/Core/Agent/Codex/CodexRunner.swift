import Foundation
import Synchronization
import os

public actor CodexRunner: SessionRunner {
    public nonisolated let agentKind = AgentKind.codex
    public nonisolated let workspacePath: String
    public nonisolated let sessionID: SessionID

    private let store: Store
    private let makeClient: @Sendable (CodexClient.Configuration) -> CodexClient

    private var session: Session
    private var client: CodexClient?
    private var pumpTask: Task<Void, Never>?
    private var leavingPumps = 0
    private var translation: CodexTranslation
    private var threadID: String?
    private var isRewinding = false
    private var planningRescanToken: String?

    private let grants: SessionGrants
    private var orchestrates = false

    private var contextWindow = CodexContextWindow.modelDefault
    private let segment: RunnerSegment

    private var wireModel: String { ModelIdentifier.resolve(session.model).model }

    private var items: [String: [String: CodexItem]] = [:]

    private var approvals: [String: CodexApprovalRequest] = [:]

    private let connection = LiveConnection()

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
        workspacePath: String,
        session: Session,
        store: Store,
        segmentID: SessionSegmentID,
        bridge: BridgeAttachment? = nil,
        account: AgentAccountHome? = nil,
        gitHub: GitHubLogin = .thisMac,
        makeClient: @escaping @Sendable (CodexClient.Configuration) -> CodexClient = CodexRunner.spawn
    ) {
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
        self.translation = CodexTranslation(context: CodexTranslation.Context(
            model: ModelIdentifier.resolve(session.model).model,
            cwd: workspacePath,
            permissionMode: session.permissionMode.rawValue
        ))
    }

    public static let spawn: @Sendable (CodexClient.Configuration) -> CodexClient = { configuration in
        CodexClient(configuration: configuration)
    }

    public nonisolated var events: AsyncStream<AgentEvent> { sink.stream() }
    public nonisolated var presentationFeed: AgentPresentationFeed? { sink }
    public nonisolated var storedMessages: StoredMessageRelay? { announced }

    public var isProcessAlive: Bool { connection.current?.isProcessAlive ?? false }

    public var hasStoppedWriting: Bool { client == nil && leavingPumps == 0 }

    public var currentSession: Session { session }

    public var lastPersistenceFailure: String? { trouble.lastSentence }

    public var persistenceFailureCount: Int { trouble.failures }

    public func send(_ text: String, recording: Data? = nil) async throws {
        try await send(text, recording: recording, deliveryID: nil, deliveredSeq: nil, interactionMode: nil)
    }

    public func evictIfIdle(for duration: Duration) async -> Bool {
        guard !wasEvicted, !isRewinding, sendsInFlight == 0, !session.state.isMidTurn,
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
        var mode = delivery.interactionMode
        if mode == nil { mode = try await store.session(id: sessionID)?.interactionMode }
        try await send(delivery.sent, recording: delivery.crewPayload, deliveryID: delivery.id,
                       deliveredSeq: try await store.delivery(id: delivery.id)?.deliveredSeq,
                       interactionMode: mode)
    }

    private func send(_ text: String, recording: Data?, deliveryID: DeliveryID?, deliveredSeq: Int?,
                      interactionMode: InteractionMode?) async throws {
        guard !wasEvicted else { throw ProviderIdleError.retired }
        guard !isRewinding else { throw ConversationRewindError.busy }
        sendsInFlight += 1
        sink.noteActivity()
        defer { sendsInFlight -= 1 }
        try await segment.refuseIfRetired { self.terminateNow() }
        let generation = handle.generation
        let replacement = handle.prepareReplacement()
        defer { handle.finishReplacement(replacement) }
        let sidePrompt = try await store.sideConversationTurn(text, sessionID: sessionID)
        await applyContextWindowChange()
        orchestrates = await grants.isOrchestrator()
        let token = try await store.setting(CodexPlanningCapability.rescanKey)
        if token != planningRescanToken, handle.turnID == nil {
            await dropConnection()
            planningRescanToken = token
        }
        try handle.check(generation)
        let client = try await connected()
        try handle.check(generation)
        let threadID = try await openThread(on: client)
        try handle.check(generation)
        var promptSeq = deliveredSeq
        if deliveryID == nil {
            let stored = if let recording {
                await persist(kind: .crew, payload: recording)
            } else {
                await persist(kind: .user, payload: Self.userPayload(text))
            }
            promptSeq = stored?.seq
        }
        try handle.check(generation)

        if let deliveryID { try await store.beginDeliveryDispatch(id: deliveryID) }
        if let turnID = handle.steerableTurnID,
           try await steer(sidePrompt, threadID: threadID, turnID: turnID, on: client) {
            if let deliveryID { try await store.acceptDelivery(id: deliveryID, providerTurnID: turnID) }
            return
        }
        try handle.check(generation)

        await segment.confirmWhatIsOwed()
        let prompt = try await store.handoffPrompt(
            sidePrompt, session: session, deliveredSeq: promptSeq,
            workspacePath: workspacePath, contextWindow: contextWindow
        )
        try handle.check(generation)
        segment.promptSent(asSteer: false, carriedDelta: prompt != sidePrompt)

        let speed = CodexSpeed.override(stored: try await store.setting(CodexSpeed.key(sessionID: session.id)))
        try handle.check(generation)
        let turn: CodexTurn
        do {
            turn = try await client.startTurn(
                threadID: threadID,
                input: [.text(prompt)],
                model: wireModel,
                effort: session.effort,
                approvalPolicy: Self.approvalPolicy(for: permissionMode),
                sandboxPolicy: Self.sandboxPolicy(for: permissionMode, writableRoot: workspacePath),
                approvalsReviewer: Self.approvalsReviewer(for: permissionMode),
                interactionMode: interactionMode ?? session.interactionMode,
                serviceTier: CodexSpeed.serviceTier(override: speed)
            )
        } catch {
            if await client.planningIsSupported == false {
                try? await store.setSetting(CodexPlanningCapability.unavailableKey, "1")
            }
            if let deliveryID, InteractionModeFailure.isDefinitiveTurnRejection(error) {
                try await store.restoreDelivery(id: deliveryID)
            }
            throw error
        }
        if await client.planningIsSupported == false {
            try? await store.setSetting(CodexPlanningCapability.unavailableKey, "1")
        }
        if let deliveryID { try await store.acceptDelivery(id: deliveryID, providerTurnID: turn.id) }
        guard handle.begin(turnID: turn.id, generation: generation) else {
            try? await client.interruptTurn(threadID: threadID, turnID: turn.id)
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
        let children = childTurns.snapshot
        Task { await self.stopTurn(stopped, children: children) }
    }

    private func stopTurn(_ stopped: CodexTurnHandle.Stopped, children: [String: String]) async {
        let connection = client
        async let family: Void = CodexFamilyStop.interrupt(children) { thread, turn, timeout in
            try? await connection?.interruptTurn(threadID: thread, turnID: turn, timeout: timeout)
        }
        if handle.generation == stopped.generation, handle.wasCancelled {
            await filePendingAsks()
        }
        await interrupt(stopped)
        await family
    }

    private func filePendingAsks() async {
        for ask in pending.drain() {
            await write(answerTo: ask, decision: .decline)
            await close(ask, as: PermissionAskOutcome.stopped, note: "")
        }
    }

    public nonisolated func terminateNow() {
        handle.markCancelled()
        connection.current?.terminateNow()
        Task { await self.shutdown() }
    }

    private func interrupt(_ stopped: CodexTurnHandle.Stopped) async {
        let target = stopped.turnID
        let client = self.client
        let threadID = self.threadID
        if handle.generation == stopped.generation, handle.wasCancelled,
           session.apply(.cancelled).moves { await save(session) }
        guard let client, let threadID, let target else { return }
        do { try await client.interruptTurn(threadID: threadID, turnID: target, timeout: .seconds(3)) } catch { client.terminateNow() }
    }

    public func answer(requestID: String, decision: PermissionDecision) async {
        guard let ask = pending.take(requestID) else { return }
        let request = approvals[requestID]
        let answerInput: JSONValue?
        if case .answer(let input) = decision { answerInput = input } else { answerInput = nil }
        await write(answerTo: ask, decision: CodexPermission.decision(for: decision), answerInput: answerInput)
        await deliverReason(of: decision, request: request)
        await close(ask, as: decision.storedName, note: "", answers: decision.answers)

        await grants.record(decision, from: ask)
    }

    public func shutdown() async {
        let intent = handle.intent
        await filePendingAsks()
        let pump = pumpTask
        let previous = detachConnection()
        previous?.terminateNow()
        if handle.intent == intent, session.apply(.cancelled).moves { await save(session) }
        await finishLeaving(previous, pump: pump)
    }

    private func dropConnection() async {
        let pump = pumpTask
        await finishLeaving(detachConnection(), pump: pump)
    }

    private func finishLeaving(_ previous: CodexClient?, pump: Task<Void, Never>?) async {
        await previous?.stop()
        await pump?.value
        leavingPumps -= 1
    }

    private func detachConnection() -> CodexClient? {
        let previous = client
        leavingPumps += 1
        client = nil
        threadID = nil
        subagents = CodexSubagents()
        backgroundCommands = CodexBackgroundCommands()
        childTurns.replace([:])
        sink.noteProcessEnded()
        items.removeAll()
        pumpTask?.cancel()
        pumpTask = nil
        handle.end()
        return previous
    }

    private func applyContextWindowChange() async {
        let stored = try? await store.setting(
            ComposerControls.contextWindowKey(sessionID: session.id)
        )
        let wanted = CodexContextWindow.normalised(stored)
        guard wanted != contextWindow else { return }
        contextWindow = wanted
        guard client != nil else { return }
        connection.current?.terminateNow()
        await dropConnection()
    }

    private func connected() async throws -> CodexClient {
        if let client { return client }

        await LoginShellPath.ready()
        let stored = try? await store.setting(AgentCatalog.executablePathSettingKey(.codex))
        let client = makeClient(CodexClient.Configuration(
            executable: AgentCatalog.executable(for: .codex, override: stored),
            cwd: workspacePath,
            account: account,
            clientName: "Unified Dev",
            clientVersion: Self.clientVersion,
            environment: gitHub.everySignIn(appliedTo: Shell.environment()),
            bridge: bridge,
            contextWindow: contextWindow
        ))
        self.client = client
        connection.attach(client)
        let events = client.events
        pumpTask = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
        try await client.start()
        return client
    }

    private func openThread(on client: CodexClient) async throws -> String {
        if let threadID { return threadID }

        orchestrates = await grants.isOrchestrator()
        let sandbox = Self.sandboxMode(for: permissionMode)
        let instructions = CodexThreadInstructions.text(
            inWorkspace: session.workspaceID != nil, orchestrates: orchestrates, hasBridge: bridge != nil
        )
        let stored = session.agentSessionID ?? ""
        let handle: CodexThreadHandle
        if stored.isEmpty {
            handle = try await startThread(on: client, sandbox: sandbox, instructions: instructions)
        } else {
            do {
                handle = try await client.resumeThread(
                    stored, cwd: workspacePath, sandbox: sandbox, developerInstructions: instructions
                )
            } catch {
                handle = try await startThread(on: client, sandbox: sandbox, instructions: instructions)
            }
        }
        if SegmentResume.lostHistory(requested: stored, received: handle.id) {
            try await segment.restartHistory()
        }

        threadID = handle.id
        if session.agentSessionID != handle.id {
            session = session.with {
                $0.agentSessionID = handle.id
                $0.updatedAt = Date()
            }
            await save(session)
        }
        return handle.id
    }

    private func startThread(
        on client: CodexClient, sandbox: CodexSandboxMode, instructions: String?
    ) async throws -> CodexThreadHandle {
        try await client.startThread(
            cwd: workspacePath,
            model: wireModel,
            approvalPolicy: Self.approvalPolicy(for: permissionMode),
            sandbox: sandbox,
            approvalsReviewer: Self.approvalsReviewer(for: permissionMode),
            developerInstructions: instructions
        )
    }

    static let clientVersion = "1.0"

    private var permissionMode: PermissionMode {
        OrchestratorToolGuard.permissionMode(session.permissionMode, orchestrates: orchestrates)
    }

    public static func approvalPolicy(for mode: PermissionMode) -> CodexApprovalPolicy {
        switch mode {
        case .bypassPermissions: .never
        case .auto, .acceptEdits, .autoReview, .plan: .onRequest
        }
    }

    public static func sandboxMode(for mode: PermissionMode) -> CodexSandboxMode {
        switch mode {
        case .bypassPermissions: .dangerFullAccess
        case .acceptEdits, .autoReview: .workspaceWrite
        case .auto, .plan: .readOnly
        }
    }

    public static func approvalsReviewer(for mode: PermissionMode) -> CodexApprovalsReviewer {
        switch mode {
        case .autoReview: .autoReview
        case .auto, .acceptEdits, .bypassPermissions, .plan: .user
        }
    }

    public static func sandboxPolicy(for mode: PermissionMode, writableRoot: String) -> JSONValue {
        switch sandboxMode(for: mode) {
        case .readOnly:
            return .object(["type": .string("readOnly")])
        case .dangerFullAccess:
            return .object(["type": .string("dangerFullAccess")])
        case .workspaceWrite:
            return .object([
                "type": .string("workspaceWrite"),
                "writableRoots": .array([.string(writableRoot)]),
                "networkAccess": .bool(false),
            ])
        }
    }

    private var subagents = CodexSubagents()

    private var backgroundCommands = CodexBackgroundCommands()
    private var backgroundOutputDirectory: URL {
        CodexBackgroundCommands.outputDirectory(besideDatabaseAt: store.path, sessionID: session.id)
    }
    private nonisolated let childTurns = CodexChildTurns()

    public nonisolated var supportsConversationRewind: Bool { true }

    public func rewind(beforeTurnID: String) async throws {
        guard !isRewinding, sendsInFlight == 0, handle.turnID == nil,
              pending.isEmpty, !sink.hasBackgroundWork else { throw ConversationRewindError.busy }
        isRewinding = true
        defer { isRewinding = false }
        let connection = try await connected()
        let thread = try await reopenStoredThread(on: connection)
        try await connection.rewindThread(threadID: thread, beforeTurnID: beforeTurnID)
        items.removeAll()
        announced.clear()
    }

    public func turnPresence(_ turnID: String) async throws -> ConversationTurnPresence {
        guard sendsInFlight == 0, handle.turnID == nil, pending.isEmpty else { throw ConversationRewindError.busy }
        guard let thread = threadID ?? storedThreadID else { return .threadMissing }
        let connection = try await connected()
        return try await connection.turnPresence(threadID: thread, turnID: turnID)
    }

    private var storedThreadID: String? {
        session.agentSessionID.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func reopenStoredThread(on client: CodexClient) async throws -> String {
        if let threadID { return threadID }
        guard let stored = storedThreadID else { throw ConversationRewindError.missingTurn }
        orchestrates = await grants.isOrchestrator()
        let handle = try await client.resumeThread(stored, cwd: workspacePath, sandbox: Self.sandboxMode(for: permissionMode))
        guard handle.id == stored else { throw ConversationRewindError.invalidHistory }
        threadID = stored
        return stored
    }

    public func subagentTranscript(for id: SubagentID) async -> SubagentTranscript? {
        guard let child = subagents.threadID(for: id), let client,
              let result = try? await client.send("thread/read", params: .object([
                  "threadId": .string(child), "includeTurns": .bool(true),
              ]), timeout: .seconds(10)),
              result["thread"]?["id"]?.stringValue == child else { return nil }
        return CodexSubagentTranscript.read(result["thread"] ?? .null, sessionID: session.id)
    }

    static func signal(for change: CodexBackgroundCommands.Change, in directory: URL) -> SubagentSignal {
        switch change {
        case .started(let start):
            return .started(start)
        case let .finished(id, status, summary, output):
            let url = CodexBackgroundCommands.outputURL(for: id, in: directory)
            let written: Bool
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try CodexBackgroundCommands.tail(of: output).write(to: url, options: .atomic)
                written = true
                pruneOutputs(in: directory)
            } catch {
                log.error("could not keep a background command's output: \(error.readableMessage, privacy: .public)")
                written = false
            }
            return .reported(SubagentReport(
                id: id, status: status, summary: summary, outputFile: written ? url.path : nil
            ))
        }
    }

    private static func pruneOutputs(in directory: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        let outputs = files.map { url in
            (url: url, modified: (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast)
        }
        for url in CodexBackgroundCommands.outdated(outputs) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                log.error("could not remove an old background command's output: \(error.readableMessage, privacy: .public)")
            }
        }
    }

    private func handle(_ event: CodexEvent) async {
        if case .itemCompleted(let item) = event, case .plan(let plan) = item.item,
           item.threadID == threadID {
            _ = try? await store.recordPlan(sessionID: session.id, sourceID: plan.id, markdown: plan.text)
        }
        if let threadID {
            let previousChildTurns = subagents.liveTurns
            for signal in subagents.receive(event, parentThreadID: threadID) {
                sink.yield(.subagent(signal))
            }
            for change in backgroundCommands.receive(event, parentThreadID: threadID) {
                sink.yield(.subagent(Self.signal(for: change, in: backgroundOutputDirectory)))
            }
            childTurns.replace(subagents.liveTurns)
            if handle.wasCancelled, let client {
                let arrived = subagents.liveTurns.filter { previousChildTurns[$0.key] != $0.value }
                if !arrived.isEmpty {
                    Task {
                        await CodexFamilyStop.interrupt(arrived) { child, turn, timeout in
                            try? await client.interruptTurn(threadID: child, turnID: turn, timeout: timeout)
                        }
                    }
                }
            }
            if let source = event.threadID, source != threadID {
                if subagents.contains(threadID: source) {
                    remember(event)
                    if case .approval(let request) = event { await ask(request) }
                }
                return
            }
            switch event {
            case .itemStarted(let item), .itemCompleted(let item):
                if case .subAgentActivity(let activity) = item.item,
                   activity.agentThreadID == threadID { return }
            default:
                break
            }
        }
        let endingTurn: String? = switch event {
        case .turnCompleted(let turn): turn.id
        case .turnError(let failure) where !failure.willRetry: failure.turnID
        default: nil
        }
        if let endingTurn, !handle.acceptsTerminal(turnID: endingTurn) { return }
        remember(event)

        if case .unknown(let method, let raw) = event, method == "serverRequest/resolved",
           let json = try? JSONDecoder().decode(JSONValue.self, from: raw),
           let id = CodexRequestID(json["params"]?["requestId"]),
           let threadID = json["params"]?["threadId"]?.stringValue {
            let requestID = CodexPermission.requestID(id, threadID: threadID)
            if let ask = pending.take(requestID) {
                await close(ask, as: PermissionAskOutcome.resolved, note: "")
                if pending.isEmpty, session.apply(.unblocked).moves { await save(session) }
            }
            return
        }

        if case .closed = event, handle.wasCancelled || trouble.hasStopped { return }

        if case .approval(let request) = event {
            await ask(request)
            return
        }

        for translated in translation.translate(event) {
            await emit(translated, endingTurn: endingTurn)
        }
    }

    private func remember(_ event: CodexEvent) {
        switch event {
        case .itemStarted(let started), .itemCompleted(let started):
            items[started.threadID, default: [:]][started.item.id] = started.item
        case .turnCompleted(let turn):
            items.removeValue(forKey: turn.threadID)
        default:
            break
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

    private func ask(_ request: CodexApprovalRequest) async {
        let item = items[request.threadID]?[request.itemID]
        let ask = CodexPermission.ask(for: request, item: item)
        if CodexPermission.asksAboutItsItem(request, item: item),
           await grants.answersItself(toolName: ask.toolName, input: ask.input) {
            await persist(kind: .system, payload: ask.raw)
            await client?.answer(request, decision: .accept)
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
            await write(answerTo: claimed, decision: CodexPermission.decision(for: decision), answerInput: nil)
            await deliverReason(of: decision, request: request)
            await close(claimed, as: decision.storedName, note: refusal)
            return
        }

        let matched = await grants.matching(ask)
        if let matched, let claimed = pending.take(ask.requestID) {
            await write(answerTo: claimed, decision: .acceptForSession)
            await close(claimed, as: PermissionAskOutcome.auto, note: PermissionGrantIndex.note(for: matched))
            await grants.recordUse(of: matched)
            return
        }

        guard matched == nil, pending.contains(ask.requestID) else { return }

        guard request.kind != .toolUserInput || request.params["isBlocking"]?.boolValue != false else { return }
        session.apply(.blocked)
        await save(session)
    }

    private func steer(
        _ text: String, threadID: String, turnID: String, on client: CodexClient
    ) async throws -> Bool {
        do {
            _ = try await client.steerTurn(threadID: threadID, turnID: turnID, input: [.text(text)])
            return true
        } catch {
            guard CodexSendRecovery.permitsNewTurn(after: error) else { throw error }
            Self.log.info("a message missed the turn it was steered into, so it starts one")
            return false
        }
    }

    private func deliverReason(of decision: PermissionDecision, request: CodexApprovalRequest?) async {
        guard case .deny(let message, let endsTurn) = decision, !endsTurn else { return }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client, let request, !request.turnID.isEmpty else { return }
        _ = try? await client.steerTurn(
            threadID: request.threadID, turnID: request.turnID, input: [.text(text)]
        )
    }

    private func write(
        answerTo ask: PermissionAsk, decision: CodexApprovalDecision, answerInput: JSONValue? = nil
    ) async {
        if let request = approvals.removeValue(forKey: ask.requestID) {
            if request.kind == .toolUserInput, let answerInput {
                await client?.answer(request.id, with: CodexQuestionnaire.result(input: answerInput, request: request))
            } else {
                await client?.answer(request, decision: decision)
            }
        }

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
        category: "codex-runner"
    )
}

private final class LiveConnection: Sendable {
    private let client = Mutex<CodexClient?>(nil)

    var current: CodexClient? { client.withLock { $0 } }

    func attach(_ client: CodexClient) {
        self.client.withLock { $0 = client }
    }
}

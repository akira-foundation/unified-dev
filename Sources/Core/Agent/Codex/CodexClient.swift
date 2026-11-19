import Foundation
import Synchronization

public actor CodexClient {
    public struct Configuration: Sendable {
        public var executable: String
        public var cwd: String
        public var account: AgentAccountHome?
        public var clientName: String
        public var clientVersion: String
        public var environment: [String: String]
        public var bridge: BridgeAttachment?
        public var contextWindow: Int

        public init(
            executable: String = CodexClient.executable,
            cwd: String,
            account: AgentAccountHome? = nil,
            clientName: String = "Unified Dev",
            clientVersion: String = "0.0.0",
            environment: [String: String] = Shell.environment(),
            bridge: BridgeAttachment? = nil,
            contextWindow: Int = CodexContextWindow.modelDefault
        ) {
            self.executable = executable
            self.cwd = cwd
            self.account = account
            self.clientName = clientName
            self.clientVersion = clientVersion
            self.environment = environment
            self.bridge = bridge
            self.contextWindow = contextWindow
        }
    }

    public static let executable = "codex"

    public static let arguments = ["app-server", "--listen", "stdio://"]

    public static func launch(_ configuration: Configuration) -> AgentLaunch {
        var arguments = Self.arguments
        if let bridge = configuration.bridge {
            arguments += BridgeRegistration.codexArguments(bridge)
        }
        arguments += CodexContextWindow.overrides(for: configuration.contextWindow)
        return AgentLaunch(
            executable: configuration.executable,
            arguments: arguments,
            cwd: configuration.cwd,
            environment: AgentAccountEnvironment.apply(launching: .codex, as: configuration.account, to: configuration.environment)
        )
    }

    private let configuration: Configuration
    private let makeProcess: @Sendable (AgentLaunch) -> any AgentProcessing
    private var process: (any AgentProcessing)?
    private let live = LiveProcess()
    private var readTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?

    private var nextRequestID = 1
    private var pending: [CodexRequestID: CheckedContinuation<JSONValue, Error>] = [:]
    private var handshakeCompleted = false
    private var collaborationModeSupported: Bool?
    public var planningIsSupported: Bool? { collaborationModeSupported }
    public func resetPlanningSupport() { collaborationModeSupported = nil }
    private var closedReason: String?

    private var stderrTail: [String] = []
    private static let stderrTailLimit = 40

    private let sink = EventFanout<CodexEvent>()

    public init(
        configuration: Configuration,
        makeProcess: @escaping @Sendable (AgentLaunch) -> any AgentProcessing = CodexClient.spawn
    ) {
        self.configuration = configuration
        self.makeProcess = makeProcess
    }

    public static let spawn: @Sendable (AgentLaunch) -> any AgentProcessing = { launch in
        StreamingProcess(
            executable: launch.executable,
            arguments: launch.arguments,
            cwd: launch.cwd,
            environment: launch.environment,
            mergeStderr: false
        )
    }

    public nonisolated var events: AsyncStream<CodexEvent> { sink.stream() }

    public var isRunning: Bool { process?.isRunning ?? false }

    public nonisolated var isProcessAlive: Bool { live.current?.isRunning ?? false }

    public var isReady: Bool { handshakeCompleted }

    public var diagnostics: [String] { stderrTail }

    public func start() async throws {
        guard process == nil else { return }

        let process = makeProcess(Self.launch(configuration))
        self.process = process
        live.attach(process)

        let errors = process.errorLines
        let lines = process.lines
        readTask = Task { [weak self] in await self?.readLines(from: lines) }
        stderrTask = Task { [weak self] in await self?.readErrors(from: errors) }

        _ = try await send(
            "initialize",
            params: .object(omittingNil: [
                "clientInfo": .object([
                    "name": .string(configuration.clientName),
                    "version": .string(configuration.clientVersion),
                ]),
                "capabilities": .object(["experimentalApi": .bool(true)]),
            ])
        )
        notify("initialized", params: nil)
        handshakeCompleted = true
    }

    public func stop() {
        terminateNow()
        finish(reason: "The Codex connection was closed")
    }

    public nonisolated func terminateNow() {
        guard let process = live.claimForSignal() else { return }
        process.closeStdin()
        process.terminate()

        Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, process.isRunning else { return }
            process.kill()
        }
    }

    public static let requestTimeout = Duration.seconds(120)

    @discardableResult
    public func send(
        _ method: String, params: JSONValue?, timeout: Duration = CodexClient.requestTimeout
    ) async throws -> JSONValue {
        if let closedReason { throw CodexClientError.connectionClosed(closedReason) }
        guard process != nil else { throw CodexClientError.notInitialized }

        let id = CodexRequestID.number(nextRequestID)
        nextRequestID += 1

        let watchdog = Task { [weak self] in
            try await Task.sleep(for: timeout)
            await self?.abandon(id, method: method, after: timeout)
        }
        defer { watchdog.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            write(CodexOutgoing.request(id: id, method: method, params: params))
        }
    }

    private func abandon(_ id: CodexRequestID, method: String, after timeout: Duration) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(
            throwing: CodexClientError.timedOut(
                method: method, seconds: Int(timeout.components.seconds)
            )
        )
    }

    public func notify(_ method: String, params: JSONValue?) {
        write(CodexOutgoing.notification(method: method, params: params))
    }

    public func answer(_ id: CodexRequestID, with result: JSONValue) {
        write(CodexOutgoing.response(id: id, result: result))
    }

    public func answer(_ request: CodexApprovalRequest, decision: CodexApprovalDecision) {
        answer(request.id, with: decision.result(for: request.kind))
    }

    private func write(_ line: String) {
        process?.writeLine(line)
    }

    public func startThread(
        cwd: String? = nil,
        model: String? = nil,
        approvalPolicy: CodexApprovalPolicy? = nil,
        sandbox: CodexSandboxMode? = nil,
        approvalsReviewer: CodexApprovalsReviewer? = nil,
        developerInstructions: String? = nil
    ) async throws -> CodexThreadHandle {
        let result = try await send("thread/start", params: .object(omittingNil: [
            "cwd": .string(cwd ?? configuration.cwd),
            "model": model.map(JSONValue.string),
            "approvalPolicy": approvalPolicy.map { .string($0.rawValue) },
            "sandbox": sandbox.map { .string($0.rawValue) },
            "approvalsReviewer": approvalsReviewer.map { .string($0.rawValue) },
            "developerInstructions": developerInstructions.map(JSONValue.string),
        ]))
        guard let id = result["thread"]?["id"]?.stringValue else {
            throw CodexClientError.unexpectedResult(method: "thread/start")
        }
        return CodexThreadHandle(
            id: id,
            model: result["model"]?.stringValue ?? "",
            effort: result["reasoningEffort"]?.stringValue
        )
    }

    @discardableResult
    public func resumeThread(
        _ threadID: String,
        cwd: String? = nil,
        model: String? = nil,
        sandbox: CodexSandboxMode? = nil,
        developerInstructions: String? = nil
    ) async throws -> CodexThreadHandle {
        let result = try await send("thread/resume", params: .object(omittingNil: [
            "threadId": .string(threadID),
            "developerInstructions": developerInstructions.map(JSONValue.string),
            "cwd": .string(cwd ?? configuration.cwd),
            "model": model.map(JSONValue.string),
            "sandbox": sandbox.map { .string($0.rawValue) },
        ]))
        return CodexThreadHandle(
            id: result["thread"]?["id"]?.stringValue ?? threadID,
            model: result["model"]?.stringValue ?? "",
            effort: result["reasoningEffort"]?.stringValue
        )
    }

    public func readConfiguration(cwd: String) async throws -> JSONValue {
        let result = try await send("config/read", params: .object([
            "cwd": .string(cwd), "includeLayers": .bool(false),
        ]))
        guard let config = result["config"], config != .null else {
            throw CodexClientError.unexpectedResult(method: "config/read")
        }
        return config
    }

    @discardableResult
    public func startTurn(
        threadID: String,
        input: [CodexUserInput],
        model: String? = nil,
        effort: String? = nil,
        approvalPolicy: CodexApprovalPolicy? = nil,
        sandboxPolicy: JSONValue? = nil,
        approvalsReviewer: CodexApprovalsReviewer? = nil,
        interactionMode: InteractionMode? = nil,
        serviceTier: String? = nil
    ) async throws -> CodexTurn {
        if interactionMode == .plan, collaborationModeSupported == false {
            throw InteractionModeFailure.unsupported
        }
        if interactionMode != nil, model?.isEmpty != false { throw InteractionModeFailure.missingModel }
        var params = JSONValue.object(omittingNil: [
            "threadId": .string(threadID),
            "input": .array(input.map(\.json)),
            "serviceTier": serviceTier.map(JSONValue.string),
            "model": model.map(JSONValue.string),
            "effort": effort.flatMap { $0.isEmpty ? nil : .string($0) },
            "approvalPolicy": approvalPolicy.map { .string($0.rawValue) },
            "sandboxPolicy": sandboxPolicy,
            "approvalsReviewer": approvalsReviewer.map { .string($0.rawValue) },
            "collaborationMode": collaborationModeSupported == false ? nil : interactionMode.flatMap { mode in
                model.map { mode.codexSettings(model: $0, effort: effort) }
            },
        ])
        let result: JSONValue
        do {
            result = try await send("turn/start", params: params)
        } catch let rejection as CodexRPCError where CodexPlanningCapability.isUnsupportedField(rejection) {
            collaborationModeSupported = false
            guard interactionMode == .build else { throw InteractionModeFailure.unsupported }
            var fields = params.objectValue ?? [:]
            fields.removeValue(forKey: "collaborationMode")
            params = .object(fields)
            result = try await send("turn/start", params: params)
        }
        return CodexTurn.decode(result["turn"] ?? .null, threadID: threadID, raw: Data())
    }

    @discardableResult
    public func steerTurn(threadID: String, turnID: String, input: [CodexUserInput]) async throws -> String {
        let result = try await send("turn/steer", params: .object([
            "threadId": .string(threadID),
            "expectedTurnId": .string(turnID),
            "input": .array(input.map(\.json)),
        ]))
        return result["turnId"]?.stringValue ?? turnID
    }

    public func interruptTurn(
        threadID: String, turnID: String, timeout: Duration = CodexClient.requestTimeout
    ) async throws {
        _ = try await send("turn/interrupt", params: .object([
            "threadId": .string(threadID),
            "turnId": .string(turnID),
        ]), timeout: timeout)
    }

    public func rewindThread(threadID: String, beforeTurnID: String) async throws {
        let metadata = try await send("thread/read", params: .object([
            "threadId": .string(threadID), "includeTurns": .bool(false),
        ]))
        guard metadata["thread"]?["id"]?.stringValue == threadID else {
            throw ConversationRewindError.invalidHistory
        }
        let historyMode = metadata["thread"]?["historyMode"]?.stringValue
        guard historyMode == nil || historyMode == "legacy" || historyMode == "paginated" else {
            throw ConversationRewindError.invalidHistory
        }
        if historyMode == "paginated" {
            _ = try await send("thread/revert", params: .object([
                "threadId": .string(threadID), "beforeTurnId": .string(beforeTurnID),
            ]))
            return
        }
        let history = try await send("thread/read", params: .object([
            "threadId": .string(threadID), "includeTurns": .bool(true),
        ]))
        guard history["thread"]?["id"]?.stringValue == threadID,
              let turns = history["thread"]?["turns"]?.arrayValue,
              turns.allSatisfy({ $0["id"]?.stringValue != nil }) else {
            throw ConversationRewindError.invalidHistory
        }
        guard let index = turns.firstIndex(where: { $0["id"]?.stringValue == beforeTurnID }) else {
            throw ConversationRewindError.missingTurn
        }
        _ = try await send("thread/rollback", params: .object([
            "threadId": .string(threadID), "numTurns": .integer(turns.count - index),
        ]))
    }

    public func threadContainsTurn(threadID: String, turnID: String) async throws -> Bool {
        let metadata = try await send("thread/read", params: .object([
            "threadId": .string(threadID), "includeTurns": .bool(false),
        ]))
        guard metadata["thread"]?["id"]?.stringValue == threadID else {
            throw ConversationRewindError.invalidHistory
        }
        let historyMode = metadata["thread"]?["historyMode"]?.stringValue
        guard historyMode == nil || historyMode == "legacy" || historyMode == "paginated" else {
            throw ConversationRewindError.invalidHistory
        }
        if historyMode != "paginated" {
            let history = try await send("thread/read", params: .object([
                "threadId": .string(threadID), "includeTurns": .bool(true),
            ]))
            guard history["thread"]?["id"]?.stringValue == threadID,
                  let turns = history["thread"]?["turns"]?.arrayValue,
                  turns.allSatisfy({ $0["id"]?.stringValue != nil }) else {
                throw ConversationRewindError.invalidHistory
            }
            return turns.contains { $0["id"]?.stringValue == turnID }
        }
        var cursor: String?
        var seen = Set<String>()
        for _ in 0..<1_000 {
            let page = try await send("thread/turns/list", params: .object([
                "threadId": .string(threadID), "limit": .integer(100),
                "sortDirection": .string("asc"), "itemsView": .string("summary"),
                "cursor": cursor.map(JSONValue.string) ?? .null,
            ]))
            guard let turns = page["data"]?.arrayValue,
                  turns.allSatisfy({ $0["id"]?.stringValue != nil }), let next = page.objectValue?["nextCursor"] else {
                throw ConversationRewindError.invalidHistory
            }
            if turns.contains(where: { $0["id"]?.stringValue == turnID }) { return true }
            if next == .null { return false }
            guard let value = next.stringValue, seen.insert(value).inserted else {
                throw ConversationRewindError.invalidHistory
            }
            cursor = value
        }
        throw ConversationRewindError.invalidHistory
    }

    public func turnPresence(threadID: String, turnID: String) async throws -> ConversationTurnPresence {
        do {
            let contains = try await threadContainsTurn(threadID: threadID, turnID: turnID)
            return contains ? .retained(threadID: threadID) : .absent(threadID: threadID)
        } catch let rejection as CodexRPCError where Self.saysThreadIsGone(rejection) {
            return .threadMissing
        }
    }

    static func saysThreadIsGone(_ rejection: CodexRPCError) -> Bool {
        rejection.code == -32600 && ["thread not loaded", "no rollout found", "missing source rollout"]
            .contains { rejection.message.contains($0) }
    }

    public func listModels(includeHidden: Bool = false) async throws -> [CodexModel] {
        let result = try await send("model/list", params: .object([
            "includeHidden": .bool(includeHidden),
        ]))
        return CodexModel.decodeList(result)
    }

    private func readLines(from lines: AsyncThrowingStream<String, Error>) async {
        do {
            for try await line in lines {
                guard let frame = CodexFrame.decode(line: line) else { continue }
                handle(frame)
            }
            finish(reason: "The Codex process ended")
        } catch {
            finish(reason: error.readableMessage)
        }
    }

    private func readErrors(from errors: AsyncStream<String>) async {
        for await line in errors {
            stderrTail.append(line)
            if stderrTail.count > Self.stderrTailLimit { stderrTail.removeFirst() }
        }
    }

    private func handle(_ frame: CodexFrame) {
        switch frame {
        case .response(let id, let result, _):
            pending.removeValue(forKey: id)?.resume(returning: result)

        case .failure(let id, let error, _):
            pending.removeValue(forKey: id)?.resume(throwing: error)

        case .request(let request):
            if let approval = CodexApprovalRequest.decode(request) {
                sink.yield(.approval(approval))
            } else {
                write(CodexOutgoing.failure(
                    id: request.id,
                    code: -32601,
                    message: "Unified Dev does not implement \(request.method)"
                ))
            }

        case .notification(let notification):
            sink.yield(CodexEvent.decode(notification))

        case .malformed(let raw):
            sink.yield(.unknown(method: "", raw: raw))
        }
    }

    private func finish(reason: String) {
        guard closedReason == nil else { return }
        closedReason = reason

        let waiters = pending
        pending.removeAll()
        for (_, continuation) in waiters {
            continuation.resume(throwing: CodexClientError.connectionClosed(reason))
        }

        sink.yield(.closed(reason: reason))
        sink.finish()
        readTask = nil
        stderrTask = nil
    }
}

private final class LiveProcess: Sendable {
    private struct State {
        var process: (any AgentProcessing)?
        var signalled = false
    }

    private let state = Mutex(State())

    var current: (any AgentProcessing)? { state.withLock(\.process) }

    func attach(_ process: any AgentProcessing) {
        state.withLock { state in
            state.process = process
            state.signalled = false
        }
    }

    func claimForSignal() -> (any AgentProcessing)? {
        state.withLock { state -> (any AgentProcessing)? in
            guard !state.signalled, let process = state.process else { return nil }
            state.signalled = true
            return process
        }
    }
}

public struct CodexThreadHandle: Sendable, Hashable {
    public let id: String
    public let model: String
    public let effort: String?

    public init(id: String, model: String = "", effort: String? = nil) {
        self.id = id
        self.model = model
        self.effort = effort
    }
}

public enum CodexApprovalPolicy: String, Sendable, Hashable, CaseIterable {
    case untrusted
    case onRequest = "on-request"
    case never
}

public enum CodexApprovalsReviewer: String, Sendable, Hashable, CaseIterable {
    case user
    case autoReview = "auto_review"
}

public enum CodexSandboxMode: String, Sendable, Hashable, CaseIterable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

public enum CodexUserInput: Sendable, Hashable {
    case text(String)
    case localImage(path: String)

    var json: JSONValue {
        switch self {
        case .text(let text):
            .object(["type": .string("text"), "text": .string(text)])
        case .localImage(let path):
            .object(["type": .string("localImage"), "path": .string(path)])
        }
    }
}

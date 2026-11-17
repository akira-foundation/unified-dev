import Foundation
import Synchronization

public actor ACPClient {
    public struct Configuration: Sendable {
        public var dialect: ACPDialect
        public var executable: String
        public var cwd: String
        public var account: AgentAccountHome?
        public var clientName: String
        public var clientVersion: String
        public var environment: [String: String]
        public var model: String
        public var effort: String
        public var alwaysApprove: Bool
        public var asksEveryCall: Bool

        public init(
            dialect: ACPDialect,
            executable: String,
            cwd: String,
            account: AgentAccountHome? = nil,
            clientName: String = "Unified Dev",
            clientVersion: String = "0.0.0",
            environment: [String: String] = Shell.environment(),
            model: String = "",
            effort: String = "",
            alwaysApprove: Bool = false,
            asksEveryCall: Bool = false
        ) {
            self.dialect = dialect
            self.executable = executable
            self.cwd = cwd
            self.account = account
            self.clientName = clientName
            self.clientVersion = clientVersion
            self.environment = environment
            self.model = model
            self.effort = effort
            self.alwaysApprove = alwaysApprove
            self.asksEveryCall = asksEveryCall
        }
    }

    public static func launch(_ configuration: Configuration) -> AgentLaunch {
        AgentLaunch(
            executable: configuration.executable,
            arguments: configuration.dialect.arguments(
                model: configuration.model,
                effort: configuration.effort,
                alwaysApprove: configuration.alwaysApprove
            ),
            cwd: configuration.cwd,
            environment: AgentAccountEnvironment.apply(configuration.account, to: configuration.environment)
                .merging(configuration.dialect.quietEnvironment) { _, ours in ours }
        )
    }

    private let configuration: Configuration
    private let makeProcess: @Sendable (AgentLaunch) -> any AgentProcessing
    private let watchdogSleep: @Sendable (Duration) async throws -> Void
    private var process: (any AgentProcessing)?
    private let live = LiveProcess()
    private var readTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?

    private var nextRequestID = 1
    private var pending: [ACPRequestID: CheckedContinuation<JSONValue, Error>] = [:]
    private var promptIDs: Set<ACPRequestID> = []
    private var handshakeCompleted = false
    private var closedReason: String?
    private var advertised: [ACPModel] = []
    private var currentModelID = ""

    private var stderrTail: [String] = []
    private static let stderrTailLimit = 40

    private let sink = EventFanout<ACPEvent>()

    public init(
        configuration: Configuration,
        makeProcess: @escaping @Sendable (AgentLaunch) -> any AgentProcessing = ACPClient.spawn,
        watchdogSleep: @escaping @Sendable (Duration) async throws -> Void = ACPClient.taskSleep
    ) {
        self.configuration = configuration
        self.makeProcess = makeProcess
        self.watchdogSleep = watchdogSleep
    }

    public static let taskSleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    public static let spawn: @Sendable (AgentLaunch) -> any AgentProcessing = { launch in
        StreamingProcess(
            executable: launch.executable,
            arguments: launch.arguments,
            cwd: launch.cwd,
            environment: launch.environment,
            mergeStderr: false
        )
    }

    public nonisolated var events: AsyncStream<ACPEvent> { sink.stream() }

    public var isRunning: Bool { process?.isRunning ?? false }

    public nonisolated var isProcessAlive: Bool { live.current?.isRunning ?? false }

    public var isClosed: Bool { closedReason != nil }

    public var isReady: Bool { handshakeCompleted }

    public var diagnostics: [String] { stderrTail }

    public func advertisedModels() -> [ACPModel] { advertised }

    public static let requestTimeout = Duration.seconds(120)

    public func start(timeout: Duration = ACPClient.requestTimeout) async throws {
        guard process == nil else { return }

        let process = makeProcess(Self.launch(configuration))
        self.process = process
        live.attach(process)

        let errors = process.errorLines
        let lines = process.lines
        readTask = Task { [weak self] in await self?.readLines(from: lines) }
        stderrTask = Task { [weak self] in await self?.readErrors(from: errors) }

        let result = try await send(
            "initialize",
            params: .object([
                "protocolVersion": .integer(1),
                "clientInfo": .object([
                    "name": .string(configuration.clientName),
                    "version": .string(configuration.clientVersion),
                ]),
                "clientCapabilities": .object([:]),
            ]),
            timeout: timeout
        )
        let modelState = result["_meta"]?["modelState"] ?? .null
        advertised = ACPModel.decodeList(modelState)
        currentModelID = modelState["currentModelId"]?.stringValue ?? ""
        notify("initialized", params: .object([:]))
        handshakeCompleted = true
    }

    public func stop() {
        terminateNow()
        finish(reason: "The \(configuration.dialect.name) connection was closed")
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

    @discardableResult
    public func send(
        _ method: String, params: JSONValue?, timeout: Duration = ACPClient.requestTimeout
    ) async throws -> JSONValue {
        if let closedReason { throw ACPClientError.connectionClosed(closedReason) }
        guard process != nil else { throw ACPClientError.notInitialized }

        let id = ACPRequestID.number(nextRequestID)
        nextRequestID += 1

        let watchdog = Task { [weak self, watchdogSleep] in
            try await watchdogSleep(timeout)
            await self?.abandon(id, method: method, after: timeout)
        }
        defer { watchdog.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            write(ACPOutgoing.request(id: id, method: method, params: params))
        }
    }

    private func abandon(_ id: ACPRequestID, method: String, after timeout: Duration) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(
            throwing: ACPClientError.timedOut(
                method: method, seconds: Int(timeout.components.seconds)
            )
        )
    }

    public func notify(_ method: String, params: JSONValue?) {
        write(ACPOutgoing.notification(method: method, params: params))
    }

    public func answer(_ id: ACPRequestID, with result: JSONValue) {
        write(ACPOutgoing.response(id: id, result: result))
    }

    private func write(_ line: String) {
        process?.writeLine(line)
    }

    public func newSession(
        cwd: String? = nil,
        mcpServers: [JSONValue] = [],
        permissionMode: PermissionMode = .auto
    ) async throws -> ACPSession {
        let result = try await send("session/new", params: sessionParams(
            sessionID: nil,
            cwd: cwd,
            mcpServers: mcpServers,
            permissionMode: permissionMode
        ))
        guard let session = ACPSession.decode(result) else {
            throw ACPClientError.unexpectedResult(method: "session/new")
        }
        if !session.models.isEmpty { advertised = session.models }
        return session
    }

    public func resumeSession(
        _ sessionID: String,
        cwd: String? = nil,
        mcpServers: [JSONValue] = [],
        permissionMode: PermissionMode = .auto
    ) async throws -> ACPSession {
        let result = try await send("session/resume", params: sessionParams(
            sessionID: sessionID,
            cwd: cwd,
            mcpServers: mcpServers,
            permissionMode: permissionMode
        ))
        if let session = ACPSession.decode(result) {
            if !session.models.isEmpty { advertised = session.models }
            return session
        }
        return ACPSession(id: sessionID, models: advertised, currentModelID: currentModelID)
    }

    public func setConfigOption(sessionID: String, configID: String, value: String) async throws {
        _ = try await send("session/set_config_option", params: .object([
            "sessionId": .string(sessionID),
            "configId": .string(configID),
            "value": configuration.dialect.configValue(value),
        ]))
    }

    @discardableResult
    public func beginPrompt(sessionID: String, text: String) throws -> ACPRequestID {
        if let closedReason { throw ACPClientError.connectionClosed(closedReason) }
        guard process != nil else { throw ACPClientError.notInitialized }
        let id = ACPRequestID.number(nextRequestID)
        nextRequestID += 1
        promptIDs.insert(id)
        write(ACPOutgoing.request(
            id: id,
            method: "session/prompt",
            params: .object([
                "sessionId": .string(sessionID),
                "prompt": .array([.object([
                    "type": .string("text"),
                    "text": .string(text),
                ])]),
            ])
        ))
        return id
    }

    public func cancel(sessionID: String) {
        notify("session/cancel", params: .object(["sessionId": .string(sessionID)]))
    }

    public func closeSession(_ sessionID: String) async {
        _ = try? await send("session/close", params: .object(["sessionId": .string(sessionID)]))
    }

    static func sessionMeta(_ permissionMode: PermissionMode, asksEveryCall: Bool) -> JSONValue {
        .object([
            "yoloMode": .bool(!asksEveryCall && permissionMode == .bypassPermissions),
            "autoMode": .bool(!asksEveryCall && (permissionMode == .auto || permissionMode == .autoReview)),
            "permissionMode": .string(permissionMode.cliValue),
        ])
    }

    private func sessionParams(
        sessionID: String?,
        cwd: String?,
        mcpServers: [JSONValue],
        permissionMode: PermissionMode
    ) -> JSONValue {
        var members: [String: JSONValue?] = [
            "cwd": .string(cwd ?? configuration.cwd),
            "mcpServers": .array(mcpServers),
        ]
        if configuration.dialect.sendsSessionMeta {
            members["_meta"] = Self.sessionMeta(permissionMode, asksEveryCall: configuration.asksEveryCall)
        }
        if let sessionID { members["sessionId"] = .string(sessionID) }
        return .object(omittingNil: members)
    }

    private func readLines(from lines: AsyncThrowingStream<String, Error>) async {
        do {
            for try await line in lines {
                guard let frame = ACPFrame.decode(line: line) else { continue }
                handle(frame)
            }
            finish(reason: "The \(configuration.dialect.name) process ended")
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

    private func handle(_ frame: ACPFrame) {
        switch frame {
        case .response(let id, let result, _):
            if promptIDs.remove(id) != nil {
                sink.yield(.promptCompleted(ACPPromptResult(
                    requestID: id,
                    sessionID: result["sessionId"]?.stringValue ?? "",
                    stopReason: result["stopReason"]?.stringValue ?? "end_turn",
                    raw: result
                )))
                return
            }
            pending.removeValue(forKey: id)?.resume(returning: result)

        case .failure(let id, let error, _):
            if promptIDs.remove(id) != nil {
                sink.yield(.promptCompleted(ACPPromptResult(
                    requestID: id,
                    sessionID: "",
                    stopReason: "refusal",
                    raw: .object(["message": .string(error.message)])
                )))
                return
            }
            pending.removeValue(forKey: id)?.resume(throwing: error)

        case .request(let request):
            if let permission = ACPPermissionRequest.decode(request) {
                sink.yield(.permission(permission))
            } else {
                write(ACPOutgoing.failure(
                    id: request.id,
                    code: -32601,
                    message: "Unified Dev does not implement \(request.method)"
                ))
            }

        case .notification(let notification):
            if notification.method == "session/update",
               let update = ACPSessionUpdate.decode(params: notification.params) {
                sink.yield(.update(update))
            } else {
                sink.yield(.unknown(method: notification.method, raw: notification.raw))
            }

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
            continuation.resume(throwing: ACPClientError.connectionClosed(reason))
        }
        promptIDs.removeAll()

        sink.yield(.closed(reason: reason))
        sink.finish()
        process = nil
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

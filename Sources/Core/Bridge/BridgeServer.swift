import Foundation
import Synchronization

public final class BridgeServer: Sendable {
    private let store: Store
    private let toolbox: BridgeToolbox
    public let registry: BridgeRegistry
    public let socketPath: String
    private let note: @Sendable (String) -> Void

    private let listener = Mutex<UnixSocketListener?>(nil)

    public let ownerToken: BridgeOwnerToken

    public init(
        store: Store,
        socketPath: String,
        registry: BridgeRegistry = BridgeRegistry(),
        toolbox: BridgeToolbox = .standard,
        note: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.store = store
        self.socketPath = socketPath
        self.registry = registry
        self.toolbox = toolbox
        self.note = note
        self.ownerToken = BridgeOwnerToken.beside(databasePath: store.path)
    }

    public convenience init(
        store: Store,
        registry: BridgeRegistry = BridgeRegistry(),
        toolbox: BridgeToolbox = .standard,
        note: @escaping @Sendable (String) -> Void = { _ in }
    ) throws {
        self.init(
            store: store,
            socketPath: try BridgeSocketPath.derive(databasePath: store.path),
            registry: registry,
            toolbox: toolbox,
            note: note
        )
    }

    public func start() throws {
        try listener.withLock { held in
            guard held == nil else { return }
            held = try UnixSocketListener(path: socketPath) { [weak self] connection in
                guard let self else {
                    connection.close()
                    return
                }
                Task { await self.serve(connection) }
            }
        }
        sweepConfigDirectory()
        admitOwner()
        note("bridge listening on \(socketPath)")
    }

    private func admitOwner() {
        do {
            registry.admit(ownerToken: try ownerToken.load())
        } catch {
            note("could not read the standalone bridge token: \(error.readableMessage)")
        }
    }

    public func ownerAttachment() -> BridgeAttachment? {
        guard let shimPath = BridgeRegistration.shimPath() else { return nil }
        guard let token = try? ownerToken.load() else { return nil }
        registry.admit(ownerToken: token)
        return BridgeAttachment(
            shimPath: shimPath,
            socketPath: socketPath,
            token: token,
            role: .owner
        )
    }

    @discardableResult
    public func regenerateOwnerToken() throws -> String {
        let token = try ownerToken.regenerate()
        registry.admit(ownerToken: token)
        note("the standalone bridge token was regenerated")
        return token
    }

    public func stop() {
        listener.withLock { held in
            held?.stop()
            held = nil
        }
    }

    public func attach(
        session: Session,
        workspace: Workspace,
        shimPath: String,
        orchestrates: Bool = false
    ) -> BridgeAttachment {
        let role = BridgeRole.workspace
        let token = registry.mint(
            sessionID: session.id, workspaceID: workspace.id, role: role, launchedOrchestrating: orchestrates,
            launchedAsking: orchestrates || BridgeProfileReach.asksTheOwner(session.permissionMode)
        )
        return BridgeAttachment(
            shimPath: shimPath,
            socketPath: socketPath,
            token: token,
            role: role
        )
    }

    public func register(session: Session, workspace: Workspace, orchestrates: Bool = false) -> BridgeHandle? {
        guard let shimPath = BridgeRegistration.shimPath() else {
            note("no bridge beside the running executable, so \(session.id) gets no bridge")
            return nil
        }
        let attachment = attach(session: session, workspace: workspace, shimPath: shimPath, orchestrates: orchestrates)
        switch session.agentKind {
        case .claudeCode, .cursor, .openCode:
            do {
                let path = try BridgeRegistration.writeClaudeConfig(
                    attachment,
                    sessionID: session.id,
                    directory: configDirectory
                )
                sweepConfigDirectory()
                return BridgeHandle(attachment: attachment, mcpConfigPath: path)
            } catch {
                note("could not write the bridge config for \(session.id): \(error.readableMessage)")
                return nil
            }
        case .codex, .grok, .antigravity:
            return BridgeHandle(attachment: attachment, mcpConfigPath: nil)
        }
    }

    public func register(askSession session: Session) -> BridgeHandle? {
        guard let owner = ownerAttachment() else {
            note("no bridge beside the running executable, so \(session.id) gets no bridge")
            return nil
        }
        let attachment = BridgeAttachment(
            shimPath: owner.shimPath,
            socketPath: owner.socketPath,
            token: registry.mintOwner(sessionID: session.id),
            role: .owner
        )
        do {
            let path = try BridgeRegistration.writeClaudeConfig(
                attachment,
                sessionID: session.id,
                directory: configDirectory
            )
            sweepConfigDirectory()
            return BridgeHandle(attachment: attachment, mcpConfigPath: path)
        } catch {
            note("could not write the bridge config for \(session.id): \(error.readableMessage)")
            return nil
        }
    }

    public func retire(sessionID: SessionID) {
        registry.retire(sessionID: sessionID)
        try? FileManager.default.removeItem(atPath: configPath(for: sessionID))
    }

    public func sweepConfigDirectory() {
        let live = registry.liveSessions
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: configDirectory) else { return }
        for name in names where name.hasSuffix(Self.configSuffix) {
            let session = SessionID(rawValue: String(name.dropLast(Self.configSuffix.count)))
            guard !live.contains(session) else { continue }
            try? manager.removeItem(atPath: (configDirectory as NSString).appendingPathComponent(name))
        }
    }

    static let configSuffix = ".mcp.json"

    public func configPath(for sessionID: SessionID) -> String {
        (configDirectory as NSString).appendingPathComponent("\(sessionID)\(Self.configSuffix)")
    }

    public var configDirectory: String {
        (socketPath as NSString).deletingPathExtension + ".d"
    }

    private func serve(_ connection: UnixSocketConnection) async {
        var iterator = connection.lines.makeAsyncIterator()

        guard let opening = await iterator.next() else {
            connection.close()
            return
        }
        guard let hello = await handshake(opening, on: connection) else {
            connection.close()
            return
        }

        while let line = await iterator.next() {
            guard let identity = registry.identity(forToken: hello.token) else { break }
            let dispatch = BridgeDispatch(store: store, identity: identity, toolbox: toolbox)
            if let reply = await dispatch.respond(to: line) {
                connection.writeLine(reply)
            }
        }
        connection.close()
    }

    private func handshake(_ line: String, on connection: UnixSocketConnection) async -> BridgeHello? {
        guard let data = line.data(using: .utf8),
              let hello = try? JSONDecoder().decode(BridgeHello.self, from: data)
        else {
            refuse("This is Unified Dev's workspace bridge and that was not a hello frame.", on: connection)
            return nil
        }
        if let problem = BridgeProtocol.problem(with: hello) {
            refuse(problem, on: connection)
            note("bridge refused a shim speaking protocol \(hello.version)")
            return nil
        }
        guard let identity = registry.identity(forToken: hello.token) else {
            refuse(BridgeProtocol.unrecognisedToken(claiming: hello.role), on: connection)
            note("bridge refused an unknown token claiming role \(hello.role)")
            return nil
        }
        if hello.role != identity.role.rawValue {
            note("bridge caller claimed role \(hello.role) and is \(identity.role.rawValue)")
        }
        if identity.role == .owner, let problem = await ownerPlacementProblem(on: connection) {
            refuse(problem, on: connection)
            note("bridge refused the owner's token from a shim running inside a workspace")
            return nil
        }
        connection.writeLine(encode(BridgeWelcome.accepting()))
        return hello
    }

    private func ownerPlacementProblem(on connection: UnixSocketConnection) async -> String? {
        guard let pid = connection.peerProcessID,
              let directory = ProcessWorkingDirectory.of(pid),
              let workspaces = try? await store.workspaces()
        else { return nil }
        return BridgeOwnerPlacement.refusal(workingDirectory: directory, workspaces: workspaces)
    }

    private func refuse(_ problem: String, on connection: UnixSocketConnection) {
        connection.writeLine(encode(BridgeWelcome.refusing(problem)))
    }

    private func encode(_ welcome: BridgeWelcome) -> String {
        guard let data = try? JSONEncoder().encode(welcome) else {
            return #"{"version":\#(BridgeProtocol.version),"accepted":false}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}

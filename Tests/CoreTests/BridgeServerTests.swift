import Foundation
import Testing
@testable import Core

@Suite("BridgeServer", .tags(.subprocess, .persistence), .scratchDirectory)
struct BridgeServerTests {
    @Test(arguments: [false, true])
    func revocationClosesAlreadyAuthenticatedClients(owner: Bool) async throws {
        let (server, sessionToken, _, session) = try await makeBridge()
        defer { server.stop() }
        let token = owner ? "test-owner-token" : sessionToken
        if owner { server.registry.admit(ownerToken: token) }
        var caller = try Caller(socketPath: server.socketPath)
        let welcome = try await caller.hello(BridgeHello(token: token, role: owner ? "owner" : "parent", shim: "test"))
        #expect(welcome.accepted)
        _ = try await caller.call(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        if owner {
            server.registry.admit(ownerToken: "replacement-owner-token")
        } else {
            server.retire(sessionID: session.id)
        }
        caller.connection.writeLine(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let reply = await caller.iterator.next()
        #expect(reply == nil)
    }

    private func makeBridge(
        origin: WorkspaceOrigin = .user
    ) async throws -> (server: BridgeServer, token: String, workspace: Workspace, session: Session) {
        let store = try makeTestStore("bridge")
        let repo = try await store.upsert(Repo(name: "billing", path: "/tmp/billing", defaultBranch: "main"))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id,
            name: "fix the index",
            branch: "unifieddev/fix-the-index",
            path: "/tmp/billing-fix-the-index",
            baseBranch: "main",
            origin: origin
        ))
        let session = try await store.upsert(Session(workspaceID: workspace.id, title: "First chat"))

        let server = try BridgeServer(store: store)
        try server.start()
        let attachment = server.attach(session: session, workspace: workspace, shimPath: "/tmp/bridge")
        return (server, attachment.token, workspace, session)
    }

    private struct Caller {
        let connection: UnixSocketConnection
        var iterator: AsyncStream<String>.AsyncIterator

        init(socketPath: String) throws {
            connection = try UnixSocketConnection.connect(to: socketPath)
            iterator = connection.lines.makeAsyncIterator()
        }

        mutating func hello(_ frame: BridgeHello) async throws -> BridgeWelcome {
            connection.writeLine(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
            let reply = try #require(await iterator.next())
            return try JSONDecoder().decode(BridgeWelcome.self, from: Data(reply.utf8))
        }

        mutating func call(_ request: String) async throws -> JSONValue {
            connection.writeLine(request)
            let reply = try #require(await iterator.next())
            return try JSONDecoder().decode(JSONValue.self, from: Data(reply.utf8))
        }
    }

    @Test("a whole MCP conversation, over the socket, answers whoami with this workspace")
    func endToEnd() async throws {
        let (server, token, workspace, session) = try await makeBridge()
        defer { server.stop() }

        var caller = try Caller(socketPath: server.socketPath)
        let welcome = try await caller.hello(BridgeHello(token: token, role: "workspace", shim: "test"))
        #expect(welcome.accepted)
        #expect(welcome.version == BridgeProtocol.version)

        let initialized = try await caller.call(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"test","version":"0"}}}"#
        )
        #expect(initialized["result"]?["protocolVersion"] == .string("2025-06-18"))
        #expect(initialized["result"]?["serverInfo"]?["name"] == .string(BridgeRegistration.serverName))
        #expect(initialized["id"] == .integer(1))

        let listed = try await caller.call(#"{"jsonrpc":"2.0","id":"two","method":"tools/list"}"#)
        #expect(listed["id"] == .string("two"))
        let names = listed["result"]?["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue }
        #expect(names == [
            "agent_list", "chat_list", "chat_read", "profile_list", "project_list", "quick_prompt_create", "quick_prompt_list",
            "whoami", "work_suggest", "work_withdraw", "workspace_diff", "workspace_rename",
        ])

        let called = try await caller.call(
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"whoami","arguments":{}}}"#
        )
        #expect(called["result"]?["isError"] == .bool(false))
        let text = try #require(called["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue)
        let answer = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))

        #expect(answer["workspace"]?["id"]?.stringValue == workspace.id.rawValue)
        #expect(answer["workspace"]?["name"]?.stringValue == "fix the index")
        #expect(answer["workspace"]?["branch"]?.stringValue == "unifieddev/fix-the-index")
        #expect(answer["project"]?["name"]?.stringValue == "billing")
        #expect(answer["session"]?["id"]?.stringValue == session.id.rawValue)
        #expect(answer["created_by"]?.stringValue == "owner")
        #expect(answer["role"]?.stringValue == "workspace")

        let readChat = try await caller.call(
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"chat_read","arguments":{"chat":"First chat"}}}"#
        )
        #expect(readChat["result"]?["isError"] == .bool(false))
        let chatText = try #require(readChat["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue)
        let chat = try #require(JSONValue.parse(chatText))
        #expect(chat["chat_id"] == .string(session.id.rawValue))
        #expect(chat["messages"] == .array([]))

        caller.connection.close()
    }

    @Test("a spawned workspace answers as a workspace, with the workspace that asked for it")
    func aSpawnedWorkspaceKnowsItsStarter() async throws {
        let parent = WorkspaceID("parent-1")
        let (server, token, _, _) = try await makeBridge(
            origin: .agent(parentWorkspaceID: parent, spawnToolUseID: "toolu_01")
        )
        defer { server.stop() }

        var caller = try Caller(socketPath: server.socketPath)
        _ = try await caller.hello(BridgeHello(token: token, role: "child", shim: "test"))
        let called = try await caller.call(
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"whoami"}}"#
        )
        let text = try #require(called["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue)
        let answer = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))

        #expect(answer["role"]?.stringValue == "workspace")
        #expect(answer["created_by"]?["agent_in_workspace"]?.stringValue == parent.rawValue)
        #expect(answer["created_by"]?["spawn_tool_use_id"]?.stringValue == "toolu_01")
        caller.connection.close()
    }

    @Test("a shim speaking another protocol version is refused, not left hanging")
    func versionSkew() async throws {
        let (server, token, _, _) = try await makeBridge()
        defer { server.stop() }

        var caller = try Caller(socketPath: server.socketPath)
        let welcome = try await caller.hello(BridgeHello(
            version: BridgeProtocol.version + 7,
            token: token,
            role: "workspace",
            shim: "/tmp/bridge"
        ))

        #expect(!welcome.accepted)
        let problem = try #require(welcome.problem)
        #expect(problem.contains("\(BridgeProtocol.version)"))
        #expect(problem.contains("\(BridgeProtocol.version + 7)"))
        #expect(problem.lowercased().contains("quit and reopen unified dev"))

        #expect(await caller.iterator.next() == nil)
    }

    @Test("a session token this launch did not mint is told to quit and reopen Unified Dev")
    func unknownToken() async throws {
        let (server, _, _, _) = try await makeBridge()
        defer { server.stop() }

        var caller = try Caller(socketPath: server.socketPath)
        let welcome = try await caller.hello(BridgeHello(token: "made up", role: "child", shim: "x"))
        #expect(!welcome.accepted)
        let problem = try #require(welcome.problem)
        #expect(problem.contains("previous launch"))
        #expect(problem.lowercased().contains("quit and reopen unified dev"))
    }

    @Test("an owner token this launch did not mint is sent to Settings, not to a restart")
    func unknownOwnerToken() async throws {
        let (server, _, _, _) = try await makeBridge()
        defer { server.stop() }

        var caller = try Caller(socketPath: server.socketPath)
        let welcome = try await caller.hello(BridgeHello(
            token: "a token from another Unified Dev",
            role: BridgeRole.owner.rawValue,
            shim: "x"
        ))

        #expect(!welcome.accepted)
        let problem = try #require(welcome.problem)
        #expect(problem.lowercased().contains("settings"))
        #expect(!problem.lowercased().contains("quit and reopen"))
        #expect(!problem.lowercased().contains("previous launch"))
        #expect(!problem.lowercased().contains("restart unifieddev"))
        #expect(problem.lowercased().contains("no retry with this token will connect"))
    }

    @Test("the unknown token sentence is chosen by the claimed role")
    func unknownTokenSentencePerRole() {
        let owner = BridgeProtocol.unrecognisedToken(claiming: BridgeRole.owner.rawValue)
        #expect(owner.contains("standalone registration"))
        #expect(!owner.lowercased().contains("quit and reopen"))
        #expect(owner.contains("regenerated in Unified Dev's Settings"))
        #expect(owner.contains("a different copy of Unified Dev"))
        #expect(!owner.lowercased().contains("same name"))

        for role in [BridgeRole.workspace.rawValue, "parent", "child", "", "something else"] {
            let session = BridgeProtocol.unrecognisedToken(claiming: role)
            #expect(session.contains("previous launch"))
            #expect(session.lowercased().contains("quit and reopen unified dev"))
            #expect(session != owner)
        }
    }

    @Test("a connection that starts talking MCP without a hello is refused")
    func noHandshake() async throws {
        let (server, _, _, _) = try await makeBridge()
        defer { server.stop() }

        let caller = try UnixSocketConnection.connect(to: server.socketPath)
        var iterator = caller.lines.makeAsyncIterator()
        caller.writeLine(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        let reply = try #require(await iterator.next())
        let welcome = try JSONDecoder().decode(BridgeWelcome.self, from: Data(reply.utf8))
        #expect(!welcome.accepted)
        caller.close()
    }

    @Test("a method the bridge does not implement is answered rather than ignored")
    func unknownMethod() async throws {
        let (server, token, _, _) = try await makeBridge()
        defer { server.stop() }

        var caller = try Caller(socketPath: server.socketPath)
        _ = try await caller.hello(BridgeHello(token: token, role: "workspace", shim: "test"))

        let reply = try await caller.call(#"{"jsonrpc":"2.0","id":9,"method":"resources/list"}"#)
        #expect(reply["error"]?["code"] == .integer(MCPErrorCode.methodNotFound))

        let unknownTool = try await caller.call(
            #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"workspace_spawn"}}"#
        )
        #expect(unknownTool["error"]?["code"] == .integer(MCPErrorCode.methodNotFound))
        caller.connection.close()
    }

    @Test("a notification is not replied to")
    func notificationsAreSilent() async throws {
        let (server, token, _, _) = try await makeBridge()
        defer { server.stop() }

        var caller = try Caller(socketPath: server.socketPath)
        _ = try await caller.hello(BridgeHello(token: token, role: "workspace", shim: "test"))

        caller.connection.writeLine(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        let reply = try await caller.call(#"{"jsonrpc":"2.0","id":42,"method":"ping"}"#)
        #expect(reply["id"] == .integer(42))
        #expect(reply["result"] != nil)
        caller.connection.close()
    }

    @Test("a server let go of is released, and its socket goes with it")
    func droppedServerIsReleased() async throws {
        let store = try makeTestStore("bridge-release")
        let socketPath = NSTemporaryDirectory() + "unifieddev-drop-\(UUID().uuidString.prefix(8)).sock"
        defer {
            try? FileManager.default.removeItem(atPath: socketPath)
            try? FileManager.default.removeItem(
                atPath: (socketPath as NSString).deletingPathExtension + ".d"
            )
        }

        weak var released: BridgeServer?
        do {
            let server = BridgeServer(store: store, socketPath: socketPath)
            try server.start()
            released = server
            #expect(released != nil)
            #expect(FileManager.default.fileExists(atPath: socketPath))
        }

        #expect(released == nil)
        #expect(!FileManager.default.fileExists(atPath: socketPath))
    }

    @Test("a config file whose token is retired does not outlive the chat that used it")
    func retiringASessionRemovesItsConfig() async throws {
        let store = try makeTestStore("bridge-retire")
        let socketPath = NSTemporaryDirectory() + "unifieddev-retire-\(UUID().uuidString.prefix(8)).sock"
        defer {
            try? FileManager.default.removeItem(atPath: socketPath)
            try? FileManager.default.removeItem(
                atPath: (socketPath as NSString).deletingPathExtension + ".d"
            )
        }
        let server = BridgeServer(store: store, socketPath: socketPath)
        defer { server.stop() }
        try server.start()

        let repo = try await store.upsert(Repo(name: "billing", path: "/tmp/billing"))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id,
            name: "w",
            branch: "b",
            path: "/tmp/w",
            baseBranch: "main",
            origin: .user
        ))
        let session = try await store.upsert(Session(workspaceID: workspace.id))
        let attachment = server.attach(session: session, workspace: workspace, shimPath: "/tmp/bridge")
        _ = try BridgeRegistration.writeClaudeConfig(
            attachment, sessionID: session.id, directory: server.configDirectory
        )
        #expect(FileManager.default.fileExists(atPath: server.configPath(for: session.id)))

        server.retire(sessionID: session.id)

        #expect(!FileManager.default.fileExists(atPath: server.configPath(for: session.id)))
        #expect(server.registry.identity(forToken: attachment.token) == nil)
    }

    @Test("starting sweeps up the config files a previous launch left behind")
    func startingSweepsTheDirectory() async throws {
        let store = try makeTestStore("bridge-sweep")
        let socketPath = NSTemporaryDirectory() + "unifieddev-sweep-\(UUID().uuidString.prefix(8)).sock"
        defer {
            try? FileManager.default.removeItem(atPath: socketPath)
            try? FileManager.default.removeItem(
                atPath: (socketPath as NSString).deletingPathExtension + ".d"
            )
        }
        let server = BridgeServer(store: store, socketPath: socketPath)
        defer { server.stop() }

        let manager = FileManager.default
        try manager.createDirectory(
            atPath: server.configDirectory, withIntermediateDirectories: true
        )
        let stale = server.configPath(for: SessionID(rawValue: "from-a-previous-launch"))
        let keep = (server.configDirectory as NSString).appendingPathComponent("notes.txt")
        try Data("{}".utf8).write(to: URL(fileURLWithPath: stale))
        try Data("not ours".utf8).write(to: URL(fileURLWithPath: keep))

        try server.start()

        #expect(!manager.fileExists(atPath: stale))
        #expect(manager.fileExists(atPath: keep))
    }
}

@Suite("BridgeServer: starting workspaces", .tags(.subprocess, .persistence), .scratchDirectory)
struct BridgeWorkspaceStartTests {
    private struct Caller {
        let connection: UnixSocketConnection
        var iterator: AsyncStream<String>.AsyncIterator

        init(socketPath: String) throws {
            connection = try UnixSocketConnection.connect(to: socketPath)
            iterator = connection.lines.makeAsyncIterator()
        }

        mutating func hello(_ frame: BridgeHello) async throws -> BridgeWelcome {
            connection.writeLine(String(decoding: try JSONEncoder().encode(frame), as: UTF8.self))
            let reply = try #require(await iterator.next())
            return try JSONDecoder().decode(BridgeWelcome.self, from: Data(reply.utf8))
        }

        mutating func call(_ request: String) async throws -> JSONValue {
            connection.writeLine(request)
            let reply = try #require(await iterator.next())
            return try JSONDecoder().decode(JSONValue.self, from: Data(reply.utf8))
        }
    }

    private final class Orders: @unchecked Sendable {
        var prompts: [String] = []
    }

    private func makeBridge(
        origin: WorkspaceOrigin = .user,
        orders: Orders,
        label: String
    ) async throws -> (server: BridgeServer, token: String) {
        let store = try makeTestStore(label)
        let repo = try await store.upsert(Repo(name: "ember", path: "/tmp/ember", defaultBranch: "main"))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id,
            name: "group occurrences",
            branch: "claude/group-occurrences",
            path: "/tmp/ember-group",
            baseBranch: "main",
            origin: origin
        ))
        let session = try await store.upsert(Session(workspaceID: workspace.id, title: "First chat"))

        let toolbox = BridgeToolbox(handlers: [
            WhoamiTool(),
            WorkspaceStartTool { order, _, _, _ in
                orders.prompts.append(order.prompt)
                return StartedWorkspaceSummary(
                    workspaceID: WorkspaceID(rawValue: "w-new"),
                    name: "Sentry importer",
                    branch: "claude/sentry-importer",
                    path: "/tmp/worktrees/w-new"
                )
            },
        ])

        let server = try BridgeServer(store: store, toolbox: toolbox)
        try server.start()
        let attachment = server.attach(session: session, workspace: workspace, shimPath: "/tmp/bridge")
        return (server, attachment.token)
    }

    @Test("a parent lists the tool and calling it starts a workspace")
    func parentCanStartOne() async throws {
        let orders = Orders()
        let (server, token) = try await makeBridge(orders: orders, label: "bridge-start-parent")
        defer { server.stop() }

        var caller = try Caller(socketPath: server.socketPath)
        #expect(try await caller.hello(BridgeHello(token: token, role: "workspace", shim: "test")).accepted)

        let listing = try await caller.call(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        let names = (listing["result"]?["tools"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
        #expect(names.contains("workspace_start"))

        let call = try await caller.call(#"""
            {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"workspace_start","arguments":{"prompt":"Import from Sentry"}}}
            """#)

        #expect(call["result"]?["isError"]?.boolValue == false)
        #expect(orders.prompts == ["Import from Sentry"])

        let text = call["result"]?["content"]?[0]?["text"]?.stringValue ?? ""
        #expect(text.contains("w-new"))
        #expect(text.contains("claude/sentry-importer"))
    }

    @Test("a workspace an agent started sees the tool, and calling it is refused")
    func agentStartedWorkspaceIsRefused() async throws {
        let orders = Orders()
        let (server, token) = try await makeBridge(
            origin: .agent(parentWorkspaceID: WorkspaceID(rawValue: "w-parent"), spawnToolUseID: "t1"),
            orders: orders,
            label: "bridge-start-spawned"
        )
        defer { server.stop() }

        var caller = try Caller(socketPath: server.socketPath)
        #expect(try await caller.hello(BridgeHello(token: token, role: "workspace", shim: "test")).accepted)

        let listing = try await caller.call(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        let names = (listing["result"]?["tools"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
        #expect(names.contains("workspace_start"))

        let call = try await caller.call(#"""
            {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"workspace_start","arguments":{"prompt":"Import from Sentry"}}}
            """#)

        #expect(call["result"]?["isError"]?.boolValue == true)
        #expect(call["result"]?["content"]?[0]?["text"]?.stringValue?.contains("itself started by an agent") == true)
        #expect(orders.prompts.isEmpty)
    }

    @Test("three starts in one turn all arrive, in order")
    func threeInOneTurn() async throws {
        let orders = Orders()
        let (server, token) = try await makeBridge(orders: orders, label: "bridge-start-three")
        defer { server.stop() }

        var caller = try Caller(socketPath: server.socketPath)
        #expect(try await caller.hello(BridgeHello(token: token, role: "workspace", shim: "test")).accepted)

        for (index, prompt) in ["Import from Sentry", "Group by release", "Faster search"].enumerated() {
            let call = try await caller.call(#"""
                {"jsonrpc":"2.0","id":\#(index + 2),"method":"tools/call","params":{"name":"workspace_start","arguments":{"prompt":"\#(prompt)"}}}
                """#)
            #expect(call["result"]?["isError"]?.boolValue == false)
        }

        #expect(orders.prompts == ["Import from Sentry", "Group by release", "Faster search"])
    }
}

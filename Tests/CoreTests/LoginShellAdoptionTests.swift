import Foundation
import Synchronization
import Testing
@testable import Core

final class ProbeWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var answered = false
    private var seen: [Bool] = []

    func install() {
        LoginShellPath.install { [self] in
            try? await Task.sleep(for: .milliseconds(400))
            lock.withLock { answered = true }
            return []
        }
    }

    func noteSpawn() {
        lock.withLock { seen.append(answered) }
    }

    var spawns: [Bool] {
        lock.withLock { seen }
    }
}

private func agentSession(_ store: Store, kind: AgentKind, model: String) async throws -> Session {
    let repo = try await store.upsert(Repo(name: "r", path: "/tmp/r-\(UUID().uuidString)"))
    let workspace = try await store.upsert(Workspace(
        repoID: repo.id, name: "w", branch: "b", path: "/tmp/w", baseBranch: "main"
    ))
    return try await store.upsert(Session(workspaceID: workspace.id, model: model, agentKind: kind))
}

@Suite(
    "Waiting for the login shell's PATH before a script runs",
    .tags(.subprocess), .scratchDirectory, .serialized, .timeLimit(.minutes(1))
)
struct LoginShellAdoptionTests {
    @Test("the probe is started once, however many times begin is called")
    func beginStartsOneProbe() async {
        let starts = Atomic<Int>(0)
        LoginShellPath.install {
            starts.add(1, ordering: .relaxed)
            return []
        }
        defer { LoginShellPath.forget() }

        LoginShellPath.begin()
        LoginShellPath.begin()
        await LoginShellPath.ready()

        #expect(starts.load(ordering: .relaxed) == 1)
    }

    @Test("ready waits for a probe already begun, and starts none of its own")
    func readyStartsNothing() async {
        let starts = Atomic<Int>(0)
        LoginShellPath.install {
            starts.add(1, ordering: .relaxed)
            return []
        }
        defer { LoginShellPath.forget() }

        await LoginShellPath.ready()

        #expect(starts.load(ordering: .relaxed) == 0)
    }

    @Test("a setup script does not start until the login shell has answered")
    func setupWaitsForTheProbe() async throws {
        let repo = try await TempRepo()
        defer { repo.cleanUp() }
        let answered = TestScratch.unique("probe-answered")

        LoginShellPath.install {
            try? await Task.sleep(for: .milliseconds(400))
            FileManager.default.createFile(atPath: answered, contents: nil)
            return []
        }
        defer { LoginShellPath.forget() }

        try repo.write(".conductor/settings.toml", """
        [scripts]
        setup = '''
        if [ -f "\(answered)" ]; then echo waited; else echo raced; fi
        '''
        """)

        let store = try makeTestStore("login-shell-adoption")
        let manager = WorkspaceManager(store: store)
        let registered = try await manager.addRepository(at: repo.path)
        let workspace = try await manager.createWorkspace(repo: registered, prompt: "Wait for the PATH")

        LoginShellPath.begin()
        let collector = LineCollector()
        let succeeded = await manager.runSetup(
            workspace: workspace, repo: registered, port: 0
        ) { collector.append($0) }

        #expect(succeeded)
        #expect(collector.joined.contains("waited"))
    }

    @Test("GitHub access neither looks for gh nor asks it until the login shell has answered")
    func gitHubAccessWaitsForTheProbe() async {
        let watch = ProbeWatch()
        watch.install()
        defer { LoginShellPath.forget() }

        LoginShellPath.begin()
        let access = await Shell.$executableLookup.withValue({ _ in
            watch.noteSpawn()
            return "/opt/mise/bin/gh"
        }) {
            await GitHub.$commandOverride.withValue({ arguments, _ in
                #expect(arguments == ["auth", "status"])
                watch.noteSpawn()
                return ShellResult(status: 0, stdout: "", stderr: "")
            }) {
                await GitHub.access()
            }
        }

        #expect(access == .ready)
        #expect(watch.spawns == [true, true])
    }

    @Test("the language server is not looked for until the login shell has answered")
    func languageServerWaitsForTheProbe() async {
        let watch = ProbeWatch()
        watch.install()
        defer { LoginShellPath.forget() }
        let server = SourceLanguageServer()

        LoginShellPath.begin()
        await #expect(throws: SourceLanguageServerError.self) {
            try await Shell.$executableLookup.withValue({ _ in
                watch.noteSpawn()
                return nil
            }) {
                _ = try await server.definition(root: "/tmp/w", path: "a.php", text: "<?php", offset: 0, language: .php)
            }
        }
        await server.close()

        #expect(watch.spawns == [true])
    }

    @Test("a Claude Code agent is not spawned until the login shell has answered")
    func claudeWaitsForTheProbe() async throws {
        let watch = ProbeWatch()
        watch.install()
        defer { LoginShellPath.forget() }
        let store = try makeTestStore("login-shell-claude")
        let session = try await agentSession(store, kind: .claudeCode, model: "opus")
        let box = ProcessBox()
        let runner = AgentRunner(
            workspacePath: "/tmp/w", session: session, store: store, segmentID: try await activeSegmentID(store, session),
            makeProcess: { launch in
                watch.noteSpawn()
                return box.factory(launch)
            }
        )

        LoginShellPath.begin()
        let sending = Task { try? await runner.send("Wait for the PATH") }
        await waitUntil("the agent was spawned") { !watch.spawns.isEmpty }
        runner.cancelNow()
        sending.cancel()

        #expect(watch.spawns == [true])
    }

    @Test("a Codex agent's client is not built until the login shell has answered")
    func codexWaitsForTheProbe() async throws {
        let watch = ProbeWatch()
        watch.install()
        defer { LoginShellPath.forget() }
        let store = try makeTestStore("login-shell-codex")
        let session = try await agentSession(store, kind: .codex, model: "gpt-5.6-sol")
        let box = ProcessBox()
        let runner = CodexRunner(
            workspacePath: "/tmp/w", session: session, store: store, segmentID: try await activeSegmentID(store, session),
            makeClient: { configuration in
                watch.noteSpawn()
                return CodexClient(configuration: configuration, makeProcess: box.factory)
            }
        )

        LoginShellPath.begin()
        let sending = Task { try? await runner.send("Wait for the PATH") }
        await waitUntil("the client was built") { !watch.spawns.isEmpty }
        runner.terminateNow()
        sending.cancel()

        #expect(watch.spawns == [true])
    }

    @Test("a Grok agent's client is not built until the login shell has answered")
    func grokWaitsForTheProbe() async throws {
        let watch = ProbeWatch()
        watch.install()
        defer { LoginShellPath.forget() }
        let store = try makeTestStore("login-shell-grok")
        let session = try await agentSession(store, kind: .grok, model: "grok-4.6")
        let box = ProcessBox()
        let runner = ACPRunner(
            dialect: .grok,
            workspacePath: "/tmp/w", session: session, store: store, segmentID: try await activeSegmentID(store, session),
            makeClient: { configuration in
                watch.noteSpawn()
                return ACPClient(configuration: configuration, makeProcess: box.factory)
            }
        )

        LoginShellPath.begin()
        let sending = Task { try? await runner.send("Wait for the PATH") }
        await waitUntil("the client was built") { !watch.spawns.isEmpty }
        runner.terminateNow()
        sending.cancel()

        #expect(watch.spawns == [true])
    }
}

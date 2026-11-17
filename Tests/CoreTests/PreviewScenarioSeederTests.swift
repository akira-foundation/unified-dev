import Testing
import Foundation
@testable import Core

@Suite("Seeding a preview scenario", .tags(.git, .subprocess), .scratchDirectory, .timeLimit(.minutes(1)))
struct PreviewScenarioSeederTests {
    private let scenario = PreviewScenario(welcome: false, projects: [
        PreviewScenario.Project(
            name: "harbour",
            files: ["src/pier.txt": "wood\n"],
            commits: ["Lay the pier", "Paint the boats"],
            remoteAhead: ["Light the lighthouse", "Ring the bell"],
            workspaces: [
                PreviewScenario.Workspace(name: "Lighthouse", branch: "lighthouse", chats: [
                    PreviewScenario.Chat(title: "Plan", messages: [
                        PreviewScenario.Line(from: .user, text: "Is the \"lamp\" lit?"),
                        PreviewScenario.Line(from: .agent, text: "Yes."),
                    ]),
                ]),
                PreviewScenario.Workspace(name: "Bell", branch: "bell"),
            ]
        ),
        PreviewScenario.Project(name: "quay"),
    ])

    private func makeSeeder() throws -> (PreviewScenarioSeeder, String) {
        let root = TestScratch.unique("preview")
        let manager = WorkspaceManager(
            store: try makeTestStore("preview"),
            workspacesRoot: URL(fileURLWithPath: root + "/workspaces", isDirectory: true)
        )
        return (PreviewScenarioSeeder(manager: manager, scratchRoot: PreviewIdentity.scratch(in: root)), root)
    }

    private func git(_ arguments: [String], in path: String) async throws -> String {
        try await Shell.check("git", arguments, cwd: path).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("projects, workspaces and chats arrive through the store, all inside the preview root")
    func seedsEverything() async throws {
        let (seeder, root) = try makeSeeder()
        let outcome = try await seeder.seed(scenario)
        #expect(outcome == PreviewScenarioSeeder.Outcome(projects: 2, workspaces: 2, chats: 1, quotas: 0))

        let store = seeder.manager.store
        let repo = try #require(try await store.repos().first { $0.name == "harbour" })
        #expect(repo.path.hasSuffix("/scratch/projects/harbour"))
        #expect(FolderPath.isInside(repo.path, of: root))
        #expect(repo.defaultBranch == "main")

        let workspaces = try await store.workspaces(repoID: repo.id)
        #expect(Set(workspaces.map(\.branch)) == ["lighthouse", "bell"])
        for workspace in workspaces {
            #expect(FolderPath.isInside(workspace.path, of: root + "/workspaces"))
            #expect(FileManager.default.fileExists(atPath: workspace.path + "/src/pier.txt"))
        }

        let lighthouse = try #require(workspaces.first { $0.branch == "lighthouse" })
        let chats = try await store.sessions(workspaceID: lighthouse.id)
        #expect(chats.map(\.title) == ["Plan"])
        let chat = try #require(chats.first)
        let messages = try await store.messages(sessionID: chat.id)
        #expect(messages.map(\.kind) == [.user, .assistantText])
        #expect(String(decoding: messages[0].payload, as: UTF8.self).contains(#"Is the \"lamp\" lit?"#))
        #expect(String(decoding: messages[1].payload, as: UTF8.self).contains("Yes."))

        let bell = try #require(workspaces.first { $0.branch == "bell" })
        #expect(try await store.sessions(workspaceID: bell.id).count == 1)
    }

    @Test("the remote holds commits the project has not fetched")
    func remoteIsAhead() async throws {
        let (seeder, _) = try makeSeeder()
        _ = try await seeder.seed(scenario)
        let project = seeder.projectsRoot + "/harbour"

        #expect(try await git(["rev-list", "--count", "HEAD"], in: project) == "2")
        #expect(try await git(["rev-list", "--count", "HEAD..origin/main"], in: project) == "0")
        try await Shell.check("git", ["fetch", "-q"], cwd: project)
        #expect(try await git(["rev-list", "--count", "HEAD..origin/main"], in: project) == "2")
        #expect(!FileManager.default.fileExists(atPath: seeder.remotesRoot + "/harbour.upstream"))

        let quay = seeder.projectsRoot + "/quay"
        #expect(try await git(["log", "--format=%s"], in: quay) == "Start quay")
        try await Shell.check("git", ["fetch", "-q"], cwd: quay)
        #expect(try await git(["rev-list", "--count", "HEAD..origin/main"], in: quay) == "0")
    }

    @Test("a scratch folder already on disk is not written over")
    func refusesAFolderInTheWay() async throws {
        let (seeder, _) = try makeSeeder()
        let inTheWay = seeder.projectsRoot + "/harbour"
        try FileManager.default.createDirectory(atPath: inTheWay, withIntermediateDirectories: true)
        try "keep".write(toFile: inTheWay + "/mine.txt", atomically: true, encoding: .utf8)

        await #expect(throws: WorkspaceError.self) { try await seeder.seed(scenario) }
        #expect(try String(contentsOfFile: inTheWay + "/mine.txt", encoding: .utf8) == "keep")
    }

    @Test("a preview that already holds projects is left as it is")
    func seedsOnce() async throws {
        let (seeder, _) = try makeSeeder()
        _ = try await seeder.seed(scenario)
        await #expect(throws: PreviewScenarioError.alreadySeeded(projects: ["harbour", "quay"])) { try await seeder.seed(scenario) }
        #expect(try await seeder.manager.store.repos().count == 2)
    }

    @Test("an invalid scenario creates nothing at all")
    func invalidCreatesNothing() async throws {
        let (seeder, root) = try makeSeeder()
        let broken = PreviewScenario(projects: [PreviewScenario.Project(name: "../out")])
        await #expect(throws: PreviewScenarioError.self) { try await seeder.seed(broken) }
        #expect(!FileManager.default.fileExists(atPath: root))
    }

    @Test("a chat line is stored in the shape the transcript reads")
    func payloadShape() throws {
        let payload = try PreviewScenarioSeeder.payload("hi", from: .user)
        let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        let message = object?["message"] as? [String: Any]
        let content = message?["content"] as? [[String: Any]]
        #expect(object?["type"] as? String == "user")
        #expect(message?["role"] as? String == "user")
        #expect(content?.first?["type"] as? String == "text")
        #expect(content?.first?["text"] as? String == "hi")
    }

    @Test("an agent line decodes as the agent's answer, so the transcript draws it")
    func agentLineDecodes() throws {
        let payload = try PreviewScenarioSeeder.payload("Yes. It was lit.", from: .agent)
        let event = AgentEvent.decode(line: String(decoding: payload, as: UTF8.self))
        guard case .assistantText(let block)? = event else {
            Issue.record("expected an assistant text event, got \(String(describing: event))")
            return
        }
        #expect(block.text == "Yes. It was lit.")
    }

    @Test("a named branch is on the remote and in the clone, with a commit of its own, and open nowhere")
    func seedsFreeBranches() async throws {
        let (seeder, _) = try makeSeeder()
        let lantern = PreviewScenario(welcome: false, projects: [
            PreviewScenario.Project(name: "lantern", commits: ["Light the wick"], branches: ["feat/shade"]),
        ])
        _ = try await seeder.seed(lantern)

        let repo = try #require(try await seeder.manager.store.repos().first)
        #expect(try await git(["rev-parse", "--abbrev-ref", "HEAD"], in: repo.path) == "main")
        #expect(try await git(["log", "-1", "--format=%s", "feat/shade"], in: repo.path) == "Start feat/shade")
        #expect(try await git(["rev-parse", "origin/feat/shade"], in: repo.path)
            == git(["rev-parse", "feat/shade"], in: repo.path))
        #expect(try await seeder.manager.store.workspaces(repoID: repo.id).isEmpty)
    }

    @Test("a remote that never answers is seeded first and only then stops answering fetches")
    func remoteThatNeverAnswers() async throws {
        let (seeder, _) = try makeSeeder()
        let quiet = PreviewScenario(welcome: false, projects: [
            PreviewScenario.Project(
                name: "fog", remoteAhead: ["Sound the horn"],
                workspaces: [PreviewScenario.Workspace(name: "Buoy", branch: "buoy")],
                remote: .never
            ),
        ])
        let outcome = try await seeder.seed(quiet)
        #expect(outcome.workspaces == 1)

        let repo = try #require(try await seeder.manager.store.repos().first)
        #expect(try await git(["config", "remote.origin.uploadpack"], in: repo.path) == "false")
        #expect(await Git.fetch("main", in: repo.path, remote: "origin") == false)
    }

    @Test("usage readings in a scenario are stored as the agents would have reported them")
    func seedsQuotas() async throws {
        let (seeder, _) = try makeSeeder()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scenario = PreviewScenario(projects: [PreviewScenario.Project(name: "quay")], quotas: [
            PreviewScenario.Quota(provider: .codex, window: "primary", hours: 168, used: 1, resetsInMinutes: 2340),
        ])
        let outcome = try await seeder.seed(scenario, at: now)
        #expect(outcome.quotas == 1)
        let stored = try await seeder.manager.store.quotas(at: now)
        #expect(stored.map(\.window.key) == ["primary"])
        #expect(stored.first?.holder == QuotaHolder(provider: .codex, account: AgentAccountHome.defaultID(for: .codex)))
        #expect(stored.first?.fraction == 1)
        #expect(stored.first?.resetsAt == now.addingTimeInterval(140_400))
    }

    @Test("a project whose name looks like an option still gets a folder of its own", arguments: [
        PreviewScenario.RemoteAnswer.absent, .promptly,
    ])
    func optionLikeNameIsAFolder(remote: PreviewScenario.RemoteAnswer) async throws {
        let (seeder, _) = try makeSeeder()
        let path = try await seeder.makeRepository(PreviewScenario.Project(name: "--bare", remote: remote))

        #expect(path == seeder.projectsRoot + "/--bare")
        #expect(FileManager.default.fileExists(atPath: path + "/.git/HEAD"))
        #expect(!FileManager.default.fileExists(atPath: seeder.projectsRoot + "/HEAD"))
    }
}

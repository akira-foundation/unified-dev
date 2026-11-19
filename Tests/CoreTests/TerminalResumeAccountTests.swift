import Testing
import Foundation
@testable import Core

@Suite("The terminal resume command runs under the account the launch decided", .tags(.persistence), .scratchDirectory)
struct TerminalResumeAccountTests {
    private let base = URL(filePath: TestScratch.unique("launch"))
    private let space = Workspace(
        repoID: RepoID("r"), name: "w", branch: "b", path: TestScratch.unique("worktree"), baseBranch: "main"
    )
    private let session = Session(workspaceID: WorkspaceID("w"), title: "Chat")

    private var client: AgentAccountHome {
        AgentAccountHome(provider: .claudeCode, id: AgentAccountID("client"), directory: URL(filePath: "/accounts/client"), isDefault: false)
    }

    private func script(_ launch: AgentAccountLaunch) throws -> String? {
        guard launch.resumeCommand(for: session, in: space, resuming: "native-id", chrome: false, base: base) != nil
        else { return nil }
        let folder = try AgentKind.interactiveLaunchDirectory(sessionID: session.id, base: base)
        return try String(contentsOf: folder.appending(path: "resume.sh"), encoding: .utf8)
    }

    @Test("a launch on this Mac's login with no account resumes with no account directory set")
    func runsWithNoAccountResumesOnTheMac() throws {
        let resume = try #require(try script(.runs(nil)))

        #expect(resume.contains("native-id"))
        #expect(!resume.contains("CLAUDE_CONFIG_DIR="))
    }

    @Test("a chosen account is the one the resumed CLI runs under")
    func aChosenAccountIsCarriedIntoTheResume() throws {
        let resume = try #require(try script(.runs(client)))

        #expect(resume.contains("native-id"))
        #expect(resume.contains("CLAUDE_CONFIG_DIR=/accounts/client"))
    }

    @Test("the resume carries the chat's model, effort, permission mode, orchestration and browser", arguments: [true, false])
    func theResumeCarriesEverySettingOfTheChat(orchestrates: Bool) throws {
        var orchestrator = space
        orchestrator.isOrchestrator = orchestrates
        let chat = Session(
            workspaceID: orchestrator.id, title: "Chat", model: "opus", effort: "high", permissionMode: .plan
        )
        let expected = URL(filePath: TestScratch.unique("expected"))
        _ = try chat.agentKind.prepareInteractiveCommand(
            directory: orchestrator.path, prompt: "", sessionID: chat.id, model: "opus", effort: "high",
            permissionMode: .plan, resuming: "native-id", account: client, orchestrates: orchestrates, chrome: true,
            base: expected
        )

        let command = AgentAccountLaunch.runs(client).resumeCommand(
            for: chat, in: orchestrator, resuming: "native-id", chrome: true, base: base
        )

        let written = try AgentKind.interactiveLaunchDirectory(sessionID: chat.id, base: base)
        let wanted = try AgentKind.interactiveLaunchDirectory(sessionID: chat.id, base: expected)
        #expect(command != nil)
        #expect(
            try String(contentsOf: written.appending(path: "resume.sh"), encoding: .utf8)
                == String(contentsOf: wanted.appending(path: "resume.sh"), encoding: .utf8)
        )
    }

    @Test("a refused agent remembers no resume command and writes no launch file")
    func aRefusedAgentRemembersNothing() throws {
        let refusal = AgentAccountRefusal(provider: .claudeCode, isChoiceLost: false)

        #expect(try script(.refused(refusal)) == nil)
        let folder = try AgentKind.interactiveLaunchDirectory(sessionID: session.id, base: base)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "resume.sh").path))
    }

    @Test("an own profile with no account chosen remembers no resume command for that agent")
    func anOwnProfileWithNoAccountResumesNothing() async throws {
        let store = try makeTestStore("terminal-resume")
        let mac = try #require(AgentAccountHome.defaultHome(for: .claudeCode, home: URL(filePath: "/Users/someone")))
        let profile = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star", accounts: .own)
        let site = try await store.upsert(Repo(name: "site", path: TestScratch.unique("repo"), profileID: profile.id))
        let own = try await AgentAccountResolver.resolve(
            workspaceID: nil, repoID: site.id, profileID: profile.id, store: store, defaults: [mac]
        )

        #expect(own.launch(for: .claudeCode).isRefused)
        #expect(try script(own.launch(for: .claudeCode)) == nil)
    }
}

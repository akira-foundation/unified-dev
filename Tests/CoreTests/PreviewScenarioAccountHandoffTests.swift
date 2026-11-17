import Foundation
import Testing
@testable import Core

@Suite("A preview scenario that moves a chat to another account of the same agent")
struct PreviewScenarioAccountHandoffTests {
    private func refusal(_ json: String) -> String {
        do {
            _ = try PreviewScenario.read(Data(json.utf8))
            return ""
        } catch {
            return String(describing: error)
        }
    }

    private func scenario(_ handoff: String, accounts: String = "") -> String {
        """
        {"accounts":[\(accounts)],"projects":[{"name":"a","workspaces":[{"name":"w","branch":"w","chats":[
          {"title":"Plan","agent":"claudeCode","model":"opus","messages":[
            {"from":"user","text":"Go"},{"from":"agent","handoff":\(handoff)}]}]}]}]}
        """
    }

    private let client = #"{"provider":"claudeCode","email":"ada@client.example","label":"client"}"#

    @Test func aMoveToADeclaredAccountOfTheSameAgentIsAccepted() throws {
        let read = try PreviewScenario.read(Data(scenario(
            #"{"agent":"claudeCode","model":"opus","account":"client"}"#, accounts: client
        ).utf8))

        #expect(read.projects[0].workspaces[0].chats[0].messages[1].handoff?.account == "client")
    }

    @Test func aMoveToAnAccountTheScenarioDoesNotDeclareIsRefused() {
        #expect(refusal(scenario(#"{"agent":"claudeCode","model":"opus","account":"client"}"#))
            .contains("which the scenario does not declare"))
    }

    @Test func aMoveToTheAccountTheChatAlreadyRunsUnderIsRefused() {
        let twice = """
        {"accounts":[\(client)],"projects":[{"name":"a","workspaces":[{"name":"w","branch":"w","chats":[
          {"title":"Plan","agent":"claudeCode","model":"opus","messages":[
            {"from":"user","text":"Go"},
            {"from":"agent","handoff":{"agent":"claudeCode","model":"opus","account":"client"}},
            {"from":"agent","handoff":{"agent":"claudeCode","model":"opus","account":"client"}}]}]}]}]}
        """

        #expect(refusal(twice).contains("already runs under"))
    }

    @Test func theTargetCarriesTheAccountAndTheNameTheDividerShows() throws {
        let account = PreviewScenario.Account(provider: .claudeCode, email: "ada@client.example", label: "client")
        let target = PreviewScenarioSeeder.target(
            of: PreviewScenario.Handoff(agent: .claudeCode, model: "opus", account: "client"), among: [account]
        )

        #expect(target.accountID == account.id)
        #expect(target.accountName == "ada@client.example")
    }

    @Test func aMoveWithNoAccountKeepsNone() {
        let target = PreviewScenarioSeeder.target(
            of: PreviewScenario.Handoff(agent: .codex, model: "gpt-5"), among: []
        )

        #expect(target.accountID == nil)
        #expect(target.accountName == nil)
    }
}

@Suite("The scenario the account switch walkthrough uses")
struct PreviewScenarioAccountHandoffFileTests {
    @Test func itHoldsAMoveBetweenTwoAccountsOfOneAgent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let read = try PreviewScenario.read(path: root + "/Tools/scenarios/switch-account-in-chat.json")
        let chats = read.projects.flatMap(\.workspaces).flatMap(\.chats)
        let moved = chats.first { chat in
            chat.messages.contains { $0.handoff?.agent == chat.agent && $0.handoff?.account != nil }
        }

        #expect(moved != nil)
    }
}

@Suite(
    "Seeding a chat that moves to another account of its agent",
    .tags(.git, .subprocess), .scratchDirectory, .timeLimit(.minutes(1))
)
struct AccountHandoffSeedingTests {
    @Test func theDividerNamesTheAccountAndTheChatEndsOnIt() async throws {
        let root = TestScratch.unique("preview-account-handoff")
        let manager = WorkspaceManager(
            store: try makeTestStore("preview-account-handoff"),
            workspacesRoot: URL(fileURLWithPath: root + "/workspaces", isDirectory: true)
        )
        let seeder = PreviewScenarioSeeder(manager: manager, scratchRoot: PreviewIdentity.scratch(in: root))
        let client = PreviewScenario.Account(provider: .claudeCode, email: "ada@client.example", label: "client")
        let workspace = PreviewScenario.Workspace(name: "Switch", branch: "switch", chats: [
            PreviewScenario.Chat(title: "Plan", agent: .claudeCode, model: "opus", messages: [
                PreviewScenario.Line(from: .user, text: "Go"),
                PreviewScenario.Line(
                    from: .agent, handoff: PreviewScenario.Handoff(agent: .claudeCode, model: "opus", account: "client")
                ),
            ]),
        ])
        let project = PreviewScenario.Project(name: "ledger", workspaces: [workspace])
        let scenario = PreviewScenario(projects: [project], accounts: [client])
        let home = URL(filePath: root + "/home", directoryHint: .isDirectory)

        let repo = try await manager.addRepository(at: try await seeder.makeRepository(project), profileID: .initial)
        try await seeder.seedAccountRows(scenario, home: home)
        _ = try await seeder.start(workspace, in: repo, accounts: scenario.accounts, at: Date())
        try await seeder.seedAccountChoices(scenario, repos: [project.name: repo.id], home: home)

        let workspaceID = try #require(try await manager.store.workspaces(repoID: repo.id).first?.id)
        let session = try #require(try await manager.store.sessions(workspaceID: workspaceID).first)
        let divider = try #require(try await manager.store.messages(sessionID: session.id).first { $0.kind == .handoff })
        #expect(HandoffMark.decode(divider.payload)?.sentence == "Continued with Claude Code under ada@client.example · opus")
        #expect(session.accountID == client.id)
    }

    @Test func aScenarioWithAccountsAndNoSeedableHomeIsRefusedBeforeAnyChat() async throws {
        let root = TestScratch.unique("preview-account-nohome")
        let manager = WorkspaceManager(
            store: try makeTestStore("preview-account-nohome"),
            workspacesRoot: URL(fileURLWithPath: root + "/workspaces", isDirectory: true)
        )
        let seeder = PreviewScenarioSeeder(manager: manager, scratchRoot: PreviewIdentity.scratch(in: root))
        let scenario = PreviewScenario(
            projects: [], accounts: [PreviewScenario.Account(email: "ada@client.example", label: "client")]
        )

        await #expect(throws: PreviewScenarioError.self) {
            try await seeder.seedAccountRows(scenario, home: nil)
        }
    }
}

import Testing
import Foundation
@testable import Core

@Suite("A refused agent's configuration is not read from this Mac's login", .tags(.persistence), .scratchDirectory)
struct RefusedAgentConfigurationTests {
    private func macLogin() throws -> SlashCommandTests.Tree {
        let tree = try SlashCommandTests.Tree()
        try tree.write(".claude/commands/mac-command.md", "---\ndescription: Mac\n---\n")
        try tree.skill(".claude/skills/mac-skill", name: "mac-skill", description: "Mac")
        try tree.write(".claude/output-styles/mac.md", "---\nname: MacStyle\ndescription: Mac\n---\n")
        try tree.skill(".codex/skills/mac-codex", name: "mac-codex", description: "Mac")
        try tree.skill(".agents/skills/mac-agents", name: "mac-agents", description: "Mac")
        try tree.skill(".codex/skills/.system/mac-system", name: "mac-system", description: "Mac")
        try tree.write(".claude/commands/project-command.md", "---\ndescription: Project\n---\n", under: tree.project)
        try tree.skill(".codex/skills/project-codex", name: "project-codex", description: "Project", under: tree.project)
        try tree.write(".claude/output-styles/project.md", "---\nname: ProjectStyle\ndescription: Project\n---\n", under: tree.project)
        return tree
    }

    private func names(_ tree: SlashCommandTests.Tree, refusing: Set<AgentKind>) -> [String] {
        SlashCommandIndex.discover(
            home: tree.home, project: tree.project, claudeHome: "\(tree.home)/.claude", refusing: refusing
        ).map(\.name)
    }

    @Test("a refused Claude Code offers none of the Mac's commands, skills or plugins")
    func refusedClaudeReadsNoMacCommands() throws {
        let tree = try macLogin()
        let root = "\(tree.home)/.claude/plugins/cache/lab/1.0.0"
        try tree.write("\(root)/skills/probe/SKILL.md", "---\nname: probe\ndescription: Lab\n---\n", under: "/")
        try tree.write("\(root)/.claude-plugin/plugin.json", #"{"name": "lab"}"#, under: "/")
        try tree.write(".claude/settings.json", #"{"enabledPlugins": {"lab@market": true}}"#)
        try tree.write(
            ".claude/plugins/installed_plugins.json",
            #"{"version": 2, "plugins": {"lab@market": [{"scope": "user", "installPath": "\#(root)"}]}}"#
        )

        let read = names(tree, refusing: [.claudeCode])

        #expect(!read.contains("mac-command"))
        #expect(!read.contains("mac-skill"))
        #expect(!read.contains("lab:probe"))
        #expect(read.contains("project-command"))
        #expect(read.contains("mac-codex"))
        #expect(read.contains("compact"))
        #expect(names(tree, refusing: []).contains("lab:probe"))
    }

    @Test("a refused Codex offers none of the Mac's skills, but the project's own")
    func refusedCodexReadsNoMacSkills() throws {
        let tree = try macLogin()

        let read = names(tree, refusing: [.codex])
        let unrefused = names(tree, refusing: [])

        #expect(!read.contains("mac-codex"))
        #expect(!read.contains("mac-agents"))
        #expect(!read.contains("mac-system"))
        #expect(unrefused.contains("mac-agents"))
        #expect(unrefused.contains("mac-system"))
        #expect(read.contains("project-codex"))
        #expect(read.contains("mac-command"))
    }

    @Test("a refused Codex offers none of the user skills it is handed, but the project's")
    func refusedCodexDropsHandedUserSkills() throws {
        let tree = try macLogin()
        let handed = [
            SlashCommand(name: "handed-user", detail: "", kind: .skill, scope: .user),
            SlashCommand(name: "handed-project", detail: "", kind: .skill, scope: .project),
        ]

        let refused = SlashCommandIndex.discover(
            home: tree.home, project: tree.project, codexSkills: handed, refusing: [.codex]
        ).map(\.name)
        let read = SlashCommandIndex.discover(home: tree.home, project: tree.project, codexSkills: handed).map(\.name)

        #expect(!refused.contains("handed-user"))
        #expect(refused.contains("handed-project"))
        #expect(read.contains("handed-user"))
    }

    @Test("a refused Claude Code offers the built-in and project output styles only")
    func refusedClaudeReadsNoMacOutputStyles() throws {
        let tree = try macLogin()

        let refused = OutputStyleIndex.discover(
            home: tree.home, project: tree.project, claudeHome: "\(tree.home)/.claude", refusing: [.claudeCode]
        ).map(\.name)
        let read = OutputStyleIndex.discover(
            home: tree.home, project: tree.project, claudeHome: "\(tree.home)/.claude"
        ).map(\.name)

        #expect(!refused.contains("MacStyle"))
        #expect(refused.contains("ProjectStyle"))
        #expect(refused.contains(OutputStyle.defaultName))
        #expect(read.contains("MacStyle"))
    }

    @Test("an own profile with no account offers none of the Mac's commands; one with an account, or that inherits, does")
    func theResolutionDecides() async throws {
        let tree = try macLogin()
        let store = try makeTestStore("refused-configuration")
        let mac = AgentAccountHome.defaultHome(for: .claudeCode, home: URL(filePath: tree.home))!
        func resolved(_ accounts: ProfileAccountSource, choosing: Bool = false) async throws -> AgentAccountResolution {
            let profile = try await store.createProfile(
                name: "P\(UUID().uuidString.prefix(6))", colour: Accent.all[1], symbol: "star", accounts: accounts
            )
            let site = try await store.upsert(Repo(name: "site", path: TestScratch.unique("repo"), profileID: profile.id))
            if choosing {
                let row = AgentAccountRow(
                    id: AgentAccountID("client-\(profile.id.rawValue)"), provider: .claudeCode,
                    directory: "\(tree.home)/.claude", profileID: profile.id
                )
                try await store.add(row)
                try await store.chooseAgentAccount(ChosenAgentAccount(AgentAccountHome(row)), forRepo: site.id)
            }
            return try await AgentAccountResolver.resolve(
                workspaceID: nil, repoID: site.id, profileID: profile.id, store: store, defaults: [mac]
            )
        }
        let own = try await resolved(.own)
        let chosen = try await resolved(.own, choosing: true)
        let heir = try await resolved(.inherits)

        #expect(own.home(for: .claudeCode) == mac)
        #expect(own.refusedProviders.contains(.claudeCode))
        #expect(!names(tree, refusing: own.refusedProviders).contains("mac-command"))
        #expect(!chosen.refusedProviders.contains(.claudeCode))
        #expect(names(tree, refusing: chosen.refusedProviders).contains("mac-command"))
        #expect(names(tree, refusing: heir.refusedProviders).contains("mac-command"))
    }

    @MainActor
    @Test("a refused reading has a style shelf of its own")
    func aRefusedReadingIsShelvedApart() {
        let shelves = OutputStyleShelves<ScanFixture>()
        let mac = AccountFixture.work

        let read = shelves.catalogue(project: "/tmp/p", account: mac)
        let refused = shelves.catalogue(project: "/tmp/p", account: mac, refusing: [.claudeCode])

        #expect(read !== refused)
        #expect(refused.refused == [.claudeCode])
        #expect(read.refused.isEmpty)
        #expect(shelves.catalogue(project: "/tmp/p", account: mac, refusing: [.claudeCode]) === refused)
    }
}

import Testing
import Foundation
@testable import Core

@Suite("A refused agent's remembered terminal resume is forgotten", .tags(.persistence), .scratchDirectory)
struct RefusedTerminalResumeTests {
    private let base = URL(filePath: TestScratch.unique("launch"))
    private let pane = "pane-1"

    private var client: AgentAccountHome {
        AgentAccountHome(provider: .claudeCode, id: AgentAccountID("client"), directory: URL(filePath: "/accounts/client"), isDefault: false)
    }

    private func remember(_ session: Session, in workspace: Workspace, store: Store) async throws -> URL {
        let command = try #require(AgentAccountLaunch.runs(client).resumeCommand(
            for: session, in: workspace, resuming: "native-id", chrome: false, base: base
        ))
        try await store.setSetting(TerminalCommandMemory.key(paneID: pane), command)
        let file = try AgentKind.interactiveLaunchDirectory(sessionID: session.id, base: base).appending(path: AgentKind.resumeFileName)
        #expect(FileManager.default.fileExists(atPath: file.path))
        return file
    }

    private func ownProfileChat(_ store: Store, accounts: ProfileAccountSource = .own) async throws -> (Workspace, Session) {
        let profile = try await store.createProfile(name: "Akira", colour: Accent.all[1], symbol: "star", accounts: accounts)
        let site = try await store.upsert(Repo(name: "site", path: TestScratch.unique("repo"), profileID: profile.id))
        let space = try await store.upsert(Workspace(
            repoID: site.id, name: "w", branch: "b", path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        let chat = try await store.upsert(Session(workspaceID: space.id, title: "Chat"))
        return (space, chat)
    }

    @Test("a refused launch forgets the pane's remembered resume and the resume file behind it")
    func aRefusedLaunchForgetsTheResume() async throws {
        let store = try makeTestStore("refused-resume")
        let (space, chat) = try await ownProfileChat(store)
        let file = try await remember(chat, in: space, store: store)
        let refusal = AgentAccountLaunch.refused(AgentAccountRefusal(provider: .claudeCode, isChoiceLost: false))

        let forgot = await refusal.forgetsResume(inPane: pane, of: chat.id, store: store, base: base)

        #expect(forgot)
        #expect(try await store.setting(TerminalCommandMemory.key(paneID: pane)) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("a launch that runs keeps the pane's remembered resume and its file")
    func aLaunchThatRunsKeepsTheResume() async throws {
        let store = try makeTestStore("running-resume")
        let (space, chat) = try await ownProfileChat(store)
        let file = try await remember(chat, in: space, store: store)

        let forgot = await AgentAccountLaunch.runs(client).forgetsResume(inPane: pane, of: chat.id, store: store, base: base)

        #expect(!forgot)
        #expect(try await store.setting(TerminalCommandMemory.key(paneID: pane)) != nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("a terminal chat in an own profile with no account chosen is refused and its resume forgotten")
    func anOwnProfileWithNoAccountForgetsTheResume() async throws {
        let store = try makeTestStore("own-profile-resume")
        let mac = try #require(AgentAccountHome.defaultHome(for: .claudeCode, home: URL(filePath: "/Users/someone")))
        let (space, chat) = try await ownProfileChat(store)
        let file = try await remember(chat, in: space, store: store)

        let launch = try #require(try await AgentAccountLaunch.terminal(of: chat.id, store: store, defaults: [mac]))
        let forgot = await launch.forgetsResume(inPane: pane, of: chat.id, store: store, base: base)

        #expect(launch.isRefused)
        #expect(forgot)
        #expect(try await store.setting(TerminalCommandMemory.key(paneID: pane)) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("a terminal chat in a profile that inherits this Mac's accounts runs and keeps its resume")
    func anInheritingProfileKeepsTheResume() async throws {
        let store = try makeTestStore("inherited-resume")
        let mac = try #require(AgentAccountHome.defaultHome(for: .claudeCode, home: URL(filePath: "/Users/someone")))
        let (space, chat) = try await ownProfileChat(store, accounts: .inherits)
        let file = try await remember(chat, in: space, store: store)

        let launch = try #require(try await AgentAccountLaunch.terminal(of: chat.id, store: store, defaults: [mac]))
        let forgot = await launch.forgetsResume(inPane: pane, of: chat.id, store: store, base: base)

        #expect(launch == .runs(mac))
        #expect(!forgot)
        #expect(try await store.setting(TerminalCommandMemory.key(paneID: pane)) != nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("a chat with no workspace has no terminal launch to decide")
    func aChatWithNoWorkspaceHasNoLaunch() async throws {
        let store = try makeTestStore("unplaced-resume")
        let chat = try await store.upsert(Session(workspaceID: nil, title: "Chat"))

        #expect(try await AgentAccountLaunch.terminal(of: chat.id, store: store) == nil)
    }

    @Test("a chat no longer in the database has no launch to decide")
    func aMissingChatHasNoLaunch() async throws {
        let store = try makeTestStore("missing-resume")

        #expect(try await AgentAccountLaunch.terminal(of: SessionID("gone"), store: store) == nil)
    }
}

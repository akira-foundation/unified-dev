import Testing
import Foundation
@testable import Core

@Suite("Setup run offer in a workspace menu", .scratchDirectory)
struct SetupRunMenuOfferTests {
    private func makeFolder(_ files: [String: String]) throws -> String {
        let root = TestScratch.unique("setup-menu")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        for (relative, contents) in files {
            let full = (root as NSString).appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                atPath: (full as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try contents.write(toFile: full, atomically: true, encoding: .utf8)
        }
        return root
    }

    private func workspace(in repo: Repo, at path: String, setupState: SetupState = .pending) -> Workspace {
        var workspace = Workspace(
            repoID: repo.id, name: "Crane", branch: "crane", path: path, baseBranch: "main"
        )
        workspace.setupState = setupState
        return workspace
    }

    private let setupFile = [".unifieddev/settings.toml": "[scripts]\nsetup = \"echo rigged\"\n"]

    @Test("a workspace never opened is offered Run Setup when its project has a setup script")
    func anUnopenedWorkspaceIsOffered() throws {
        let repo = Repo(name: "dockyard", path: try makeFolder(setupFile))
        let opened = workspace(in: repo, at: try makeFolder([:]))
        let presence = SetupScriptPresence.read(repos: [repo], workspaces: [opened], homePaths: [])

        let offer = try #require(SetupRunOffer.menuOffer(for: opened, presence: presence, live: nil))
        #expect(offer.title == "Run Setup")
        #expect(offer.isEnabled)
    }

    @Test("a workspace whose setup already ran or failed is offered it again, unopened")
    func anUnopenedWorkspaceAfterARunIsOfferedAgain() throws {
        let repo = Repo(name: "dockyard", path: try makeFolder(setupFile))
        for state in [SetupState.failed, .succeeded, .skipped, .ignored] {
            let unopened = workspace(in: repo, at: try makeFolder([:]), setupState: state)
            let presence = SetupScriptPresence.read(repos: [repo], workspaces: [unopened], homePaths: [])
            let offer = try #require(SetupRunOffer.menuOffer(for: unopened, presence: presence, live: nil))
            #expect(offer.title == "Run Setup Again")
            #expect(offer.isEnabled)
        }
    }

    @Test("a stored log alone counts as a first run, as it does for an open workspace")
    func aStoredLogCountsAsARun() throws {
        let repo = Repo(name: "dockyard", path: try makeFolder(setupFile))
        var unopened = workspace(in: repo, at: try makeFolder([:]))
        unopened.setupLog = "rigged\n"
        let presence = SetupScriptPresence.read(repos: [repo], workspaces: [unopened], homePaths: [])
        let offer = try #require(SetupRunOffer.menuOffer(for: unopened, presence: presence, live: nil))
        #expect(offer.title == "Run Setup Again")
    }

    @Test("a project with no setup script offers nothing, opened or not")
    func noScriptNoItem() throws {
        let repo = Repo(name: "quay", path: try makeFolder(["README.md": "# Quay\n"]))
        let unopened = workspace(in: repo, at: try makeFolder([:]))
        let presence = SetupScriptPresence.read(repos: [repo], workspaces: [unopened], homePaths: [])
        #expect(SetupRunOffer.menuOffer(for: unopened, presence: presence, live: nil) == nil)
    }

    @Test("submodules in the worktree are a setup of their own, with no script")
    func submodulesAreASetup() throws {
        let repo = Repo(name: "quay", path: try makeFolder(["README.md": "# Quay\n"]))
        let withModules = workspace(in: repo, at: try makeFolder([".gitmodules": "[submodule \"x\"]\n"]))
        let without = workspace(in: repo, at: try makeFolder([:]))
        let presence = SetupScriptPresence.read(
            repos: [repo], workspaces: [withModules, without], homePaths: []
        )
        #expect(SetupRunOffer.menuOffer(for: withModules, presence: presence, live: nil)?.title == "Run Setup")
        #expect(SetupRunOffer.menuOffer(for: without, presence: presence, live: nil) == nil)
    }

    @Test("a workspace of a project nobody has read yet offers nothing rather than guessing")
    func unreadPresenceOffersNothing() throws {
        let repo = Repo(name: "dockyard", path: try makeFolder(setupFile))
        let unopened = workspace(in: repo, at: try makeFolder([:]))
        #expect(SetupRunOffer.menuOffer(for: unopened, presence: SetupScriptPresence(), live: nil) == nil)
    }

    @Test("an open workspace answers from what its model holds, not from the stored row")
    func theLiveModelWins() throws {
        let repo = Repo(name: "dockyard", path: try makeFolder(setupFile))
        let opened = workspace(in: repo, at: try makeFolder([:]))
        let presence = SetupScriptPresence.read(repos: [repo], workspaces: [opened], homePaths: [])

        let running = SetupRunOffer.Live(hasSetupScript: true, hasRunSetup: true, isRunning: true)
        let offer = try #require(SetupRunOffer.menuOffer(for: opened, presence: presence, live: running))
        #expect(offer.title == "Run Setup Again")
        #expect(offer.isEnabled == false)

        let removed = SetupRunOffer.Live(hasSetupScript: false, hasRunSetup: false, isRunning: false)
        #expect(SetupRunOffer.menuOffer(for: opened, presence: presence, live: removed) == nil)
    }

    @Test("a script the model has just read reaches the menu of every workspace of that project")
    func aModelReadingUpdatesItsProject() throws {
        let repo = Repo(name: "dockyard", path: try makeFolder([:]))
        let other = workspace(in: repo, at: try makeFolder([:]))
        var presence = SetupScriptPresence.read(repos: [repo], workspaces: [other], homePaths: [])
        #expect(SetupRunOffer.menuOffer(for: other, presence: presence, live: nil) == nil)

        presence.record(repoID: repo.id, hasSetupScript: true)
        #expect(SetupRunOffer.menuOffer(for: other, presence: presence, live: nil)?.title == "Run Setup")

        presence.record(repoID: repo.id, hasSetupScript: false)
        #expect(SetupRunOffer.menuOffer(for: other, presence: presence, live: nil) == nil)
    }
}

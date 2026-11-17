import Testing
import Foundation
@testable import Core

@Suite("Every gh call and agent runs under its profile's GitHub login", .tags(.persistence), .scratchDirectory)
struct GitHubLoginRoutingTests {
    private func seed(_ store: Store, in profile: ProfileID) async throws -> (repo: Repo, workspace: Workspace) {
        let repo = try await store.upsert(Repo(name: "r", path: TestScratch.unique("repo"), profileID: profile))
        let workspace = try await store.upsert(Workspace(
            repoID: repo.id, name: "billing", branch: "feature/w",
            path: TestScratch.unique("worktree"), baseBranch: "main"
        ))
        return (repo, workspace)
    }

    @Test func aNewProfileUsesUnifiedsLoginAndCanTakeItsOwn() async throws {
        let store = try makeTestStore("github-login")
        let debtges = try await store.createProfile(name: "Debtges", colour: Accent.all[1], symbol: "star")
        #expect(store.gitHubLogin(for: debtges.id) == .thisMac)

        try await store.setGitHubSource(.own, for: debtges.id)
        let login = store.gitHubLogin(for: debtges.id)
        let support = URL(filePath: store.path).deletingLastPathComponent()
        #expect(login.directory?.path == ProfileGitHubLogins.root(support: support).appending(path: debtges.id.rawValue).path)

        try await store.setGitHubSource(.own, for: .initial)
        #expect(store.gitHubLogin(for: .initial) == .thisMac)

        let reopened = try Store(path: store.path)
        #expect(reopened.gitHubLogin(for: debtges.id) == login)

        try await reopened.setGitHubSource(.inherits, for: debtges.id)
        #expect(reopened.gitHubLogin(for: debtges.id) == .thisMac)
    }

    @Test func aDatabaseFromBeforeGivesEveryProfileUnifiedsLogin() async throws {
        let first = try makeTestStore("github-login-before")
        let debtges = try await first.createProfile(name: "Debtges", colour: Accent.all[1], symbol: "star")
        let raw = try SQLiteDatabase(path: first.path)
        let version = try raw.readUserVersion()
        try raw.execute("ALTER TABLE profiles DROP COLUMN github_source;")
        try raw.setUserVersion(version - 3)

        let reopened = try Store(path: first.path)
        #expect(reopened.gitHubLogins().source(of: debtges.id) == .inherits)
        try await reopened.setGitHubSource(.own, for: debtges.id)
        #expect(reopened.gitHubLogins().source(of: debtges.id) == .own)
    }

    @Test func aWorktreeResolvesToItsProjectsProfile() async throws {
        let store = try makeTestStore("github-login-route")
        let debtges = try await store.createProfile(name: "Debtges", colour: Accent.all[1], symbol: "star")
        try await store.setGitHubSource(.own, for: debtges.id)
        let (repo, workspace) = try await seed(store, in: debtges.id)
        let (unifiedRepo, _) = try await seed(store, in: .initial)

        #expect(await store.gitHubLogin(forDirectory: workspace.path) == store.gitHubLogin(for: debtges.id))
        #expect(await store.gitHubLogin(forDirectory: repo.path + "/Sources") == store.gitHubLogin(for: debtges.id))
        #expect(await store.gitHubLogin(forDirectory: unifiedRepo.path) == .thisMac)
        #expect(await store.gitHubLogin(forDirectory: "/nowhere") == .thisMac)
    }

    @Test func aDirectoryReachedThroughALinkStillFindsItsProfile() async throws {
        let store = try makeTestStore("github-login-link")
        let debtges = try await store.createProfile(name: "Debtges", colour: Accent.all[1], symbol: "star")
        try await store.setGitHubSource(.own, for: debtges.id)
        let real = URL(filePath: TestScratch.unique("linked-real")).resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        let link = TestScratch.unique("linked-alias")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        _ = try await store.upsert(Repo(name: "r", path: real, profileID: debtges.id))
        let elsewhere = URL(filePath: TestScratch.unique("linked-other")).resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: true)
        let recordedThroughLink = TestScratch.unique("linked-recorded")
        try FileManager.default.createSymbolicLink(atPath: recordedThroughLink, withDestinationPath: elsewhere)
        _ = try await store.upsert(Repo(name: "o", path: recordedThroughLink, profileID: debtges.id))

        #expect(await store.gitHubLogin(forDirectory: link) == store.gitHubLogin(for: debtges.id))
        #expect(await store.gitHubLogin(forDirectory: elsewhere) == store.gitHubLogin(for: debtges.id))
    }

    @Test func aRouteFollowsAWorkspaceOrProjectWhosePathChangesAtTheSameLength() async throws {
        let store = try makeTestStore("github-login-respelled")
        let debtges = try await store.createProfile(name: "Debtges", colour: Accent.all[1], symbol: "star")
        try await store.setGitHubSource(.own, for: debtges.id)
        let (repo, workspace) = try await seed(store, in: debtges.id)
        let own = store.gitHubLogin(for: debtges.id)
        #expect(await store.gitHubLogin(forDirectory: workspace.path) == own)

        let moved = String(workspace.path.dropLast()) + "Z"
        _ = try await store.update(workspaceID: workspace.id) { $0.path = moved }
        #expect(await store.gitHubLogin(forDirectory: moved) == own)

        let replacement = String(repo.path.dropLast()) + "Z"
        try await store.deleteRepo(id: repo.id)
        _ = try await store.upsert(Repo(name: "r", path: replacement, profileID: debtges.id))
        #expect(await store.gitHubLogin(forDirectory: replacement) == own)
    }

    @Test func movingAProjectMovesItsLogin() async throws {
        let store = try makeTestStore("github-login-move")
        let debtges = try await store.createProfile(name: "Debtges", colour: Accent.all[1], symbol: "star")
        try await store.setGitHubSource(.own, for: debtges.id)
        let (repo, workspace) = try await seed(store, in: .initial)
        #expect(await store.gitHubLogin(forDirectory: workspace.path) == .thisMac)

        try await store.move(repoID: repo.id, to: debtges.id)
        #expect(await store.gitHubLogin(forDirectory: workspace.path) == store.gitHubLogin(for: debtges.id))
    }

    @Test func gitFetchAndCloneCarryTheLoginOfTheirProject() async throws {
        let bin = TestScratch.unique("fake-git")
        try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
        let record = bin + "/seen"
        let script = bin + "/git"
        try "#!/bin/sh\nprintf '%s\\n' \"$GH_CONFIG_DIR\" >> '\(record)'\n"
            .write(toFile: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
        let own = GitHubLogin.profile(ProfileID("debtges"), directory: URL(filePath: "/support/GitHubLogins/debtges"))

        try await Shell.$executableLookup.withValue({ _ in script }) {
            try await GitHub.$login.withValue(own) {
                _ = await Git.fetchBranches(from: "origin", in: bin)
                try await Git.clone("https://github.com/example/site.git", into: bin + "/clone/site")
            }
        }
        let seen = try String(contentsOfFile: record, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(seen == ["/support/GitHubLogins/debtges", "/support/GitHubLogins/debtges"])
    }

    @Test func gitFindsTheLoginFromTheDirectoryItFetchesInOrClonesInto() async throws {
        let bin = TestScratch.unique("fake-git-routed")
        try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
        let record = bin + "/seen"
        let script = bin + "/git"
        try "#!/bin/sh\nprintf '%s\\n' \"${GH_CONFIG_DIR-unset}\" >> '\(record)'\n"
            .write(toFile: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
        let own = GitHubLogin.profile(ProfileID("debtges"), directory: URL(filePath: "/support/GitHubLogins/debtges"))
        let project = bin + "/project"
        let destination = bin + "/clone/site"
        let routed: Set<String> = [project, destination]

        try await Shell.$executableLookup.withValue({ _ in script }) {
            try await GitHub.$loginResolverOverride.withValue({ routed.contains($0) ? own : nil }) {
                try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
                _ = await Git.fetchBranches(from: "origin", in: project)
                _ = await Git.fetchBranches(from: "origin", in: bin)
                try await Git.clone("https://github.com/example/site.git", into: destination)
            }
        }
        let seen = try String(contentsOfFile: record, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(seen.count == 3)
        #expect(seen.first == "/support/GitHubLogins/debtges")
        #expect(seen.dropFirst().first != "/support/GitHubLogins/debtges")
        #expect(seen.last == "/support/GitHubLogins/debtges")
    }

    @Test func aChatRunsUnderTheLoginOfItsWorkspacesProfileOrTheProfileItIsPinnedTo() async throws {
        let store = try makeTestStore("github-login-scope")
        let debtges = try await store.createProfile(name: "Debtges", colour: Accent.all[1], symbol: "star")
        try await store.setGitHubSource(.own, for: debtges.id)
        let (_, workspace) = try await seed(store, in: debtges.id)
        let own = store.gitHubLogin(for: debtges.id)

        let workspaceChat = AccountScope.chat(workspace: workspace, activeProfile: .initial, pinnedProfile: nil)
        #expect(await store.gitHubLogin(for: workspaceChat) == own)

        let askChat = AccountScope.chat(workspace: nil, activeProfile: .initial, pinnedProfile: debtges.id)
        #expect(await store.gitHubLogin(for: askChat) == own)
        #expect(await store.gitHubLogin(for: AccountScope.none) == .thisMac)
    }

    @Test func aChangedLoginRetiresTheRunnerAndKeepsItsOwnRateLimit() async throws {
        let (_, made) = try await LaunchAccountFixture.session(kind: .claudeCode)
        let own = GitHubLogin.profile(ProfileID("debtges"), directory: URL(filePath: "/support/GitHubLogins/debtges"))
        let segment = SessionSegmentID("segment")
        let before = AgentRunnerFingerprint(session: made, account: nil, orchestrates: false, segment: segment)
        let after = AgentRunnerFingerprint(session: made, account: nil, orchestrates: false, segment: segment, gitHub: own)
        #expect(before != after)

        let mac = GitHubRequests.Key(host: "github.com", directory: nil, arguments: [])
        let profile = GitHubRequests.Key(host: "github.com", directory: nil, arguments: [], login: own)
        #expect(mac.limitedHost == "github.com")
        #expect(profile.limitedHost != mac.limitedHost)
    }

    @Test func ghAndGitAreStartedWithTheLoginsEnvironment() async throws {
        let bin = TestScratch.unique("fake-gh")
        try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
        let script = bin + "/echo-login"
        try "#!/bin/sh\nprintf '%s|%s' \"$GH_CONFIG_DIR\" \"${GH_TOKEN-unset}\"\n"
            .write(toFile: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
        let own = GitHubLogin.profile(ProfileID("debtges"), directory: URL(filePath: "/support/GitHubLogins/debtges"))

        let answers = try await Shell.$executableLookup.withValue({ _ in script }) {
            try await GitHub.$login.withValue(own) {
                [
                    try await GitHub.run("gh", ["api", "user"]).stdout,
                    try await GitHub.run("git", ["push"]).stdout,
                ]
            }
        }
        let refused = "/support/GitHubLogins/debtges|" + GitHubLogin.signedOutToken
        #expect(answers == [refused, refused])
    }

    @Test func ghRunsUnderTheLoginOfTheDirectoryItRunsIn() async throws {
        let own = GitHubLogin.profile(ProfileID("debtges"), directory: URL(filePath: "/support/GitHubLogins/debtges"))
        let worktree = TestScratch.unique("routed")
        let seen = LoginLog()
        _ = try await GitHub.$loginResolverOverride.withValue({ directory in directory == worktree ? own : nil }) {
            try await GitHub.$commandOverride.withValue({ _, _ in
                await seen.record(GitHub.login)
                return ShellResult(status: 0, stdout: "", stderr: "")
            }) {
                _ = try await GitHub.run("gh", ["api", "user"], cwd: worktree)
                _ = try await GitHub.run("gh", ["api", "rate_limit"], cwd: TestScratch.unique("elsewhere"))
                _ = try await GitHub.$login.withValue(.thisMac) {
                    try await GitHub.run("gh", ["api", "emojis"], cwd: worktree)
                }
            }
        }
        #expect(await seen.logins == [own, .thisMac, .thisMac])
    }

    @Test func signedInCheckAsksUnderTheLoginItIsGiven() async {
        let own = GitHubLogin.profile(ProfileID("debtges"), directory: URL(filePath: "/support/GitHubLogins/debtges"))
        let seen = LoginLog()
        let access = await Shell.$executableLookup.withValue({ _ in "/usr/local/bin/gh" }) {
            await GitHub.$commandOverride.withValue({ arguments, _ in
                await seen.record(GitHub.login)
                return ShellResult(status: arguments == ["auth", "status"] ? 1 : 0, stdout: "", stderr: "")
            }) {
                await GitHub.access(login: own)
            }
        }
        #expect(access == .signedOut)
        #expect(await seen.logins == [own])
    }

    @Test func aWorkspaceTerminalCarriesItsProfilesLogin() async throws {
        let store = try makeTestStore("github-login-terminal")
        let debtges = try await store.createProfile(name: "Debtges", colour: Accent.all[1], symbol: "star")
        let (repo, workspace) = try await seed(store, in: debtges.id)
        let manager = WorkspaceManager(store: store)

        #expect(manager.environment(for: workspace, repo: repo, port: 3000)["GH_CONFIG_DIR"] == nil)

        try await store.setGitHubSource(.own, for: debtges.id)
        let variables = manager.environment(for: workspace, repo: repo, port: 3000)
        #expect(variables["GH_CONFIG_DIR"] == store.gitHubLogin(for: debtges.id).directory?.path)
        #expect(variables["GH_TOKEN"] == GitHubLogin.signedOutToken)
    }

    @Test func anAgentLaunchCarriesTheLoginAndDropsInheritedTokens() async throws {
        let (store, made) = try await LaunchAccountFixture.session(kind: .claudeCode)
        let own = GitHubLogin.profile(ProfileID("debtges"), directory: URL(filePath: "/support/GitHubLogins/debtges"))
        let runner = AgentRunner(
            workspacePath: "/tmp/w", session: made, store: store, segmentID: try await activeSegmentID(store, made),
            gitHub: own, inheritedEnvironment: ["GH_TOKEN": "inherited", "GITHUB_TOKEN": "inherited", "PATH": "/bin"]
        )
        let launch = await runner.launch()
        #expect(launch.environment["GH_CONFIG_DIR"] == "/support/GitHubLogins/debtges")
        #expect(launch.environment["GH_TOKEN"] == GitHubLogin.signedOutToken)
        #expect(launch.environment["GH_ENTERPRISE_TOKEN"] == GitHubLogin.signedOutToken)
        #expect(launch.environment["GITHUB_TOKEN"] == nil)
    }
}

private actor LoginLog {
    private(set) var logins: [GitHubLogin?] = []

    func record(_ login: GitHubLogin?) {
        logins.append(login)
    }
}

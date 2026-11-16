import Testing
import Foundation
@testable import Core

@Suite("Script environment")
struct ScriptEnvironmentTests {
    private let repo = Repo(id: RepoID("r1"), name: "There There", path: "/tmp/there", defaultBranch: "main")

    private func makeEnvironment(port: Int = 3_100) throws -> [String: String] {
        let workspace = Workspace(
            id: WorkspaceID("w1"),
            repoID: repo.id,
            name: "Fix the inbox",
            branch: "freek/fix-the-inbox",
            path: "/tmp/there-fix-the-inbox",
            baseBranch: "main"
        )
        let manager = WorkspaceManager(store: try Store.inMemory())
        return manager.environment(for: workspace, repo: repo, port: port)
    }

    @Test("UD_ is the interface, and it is complete")
    func unifieddevNamesAreTheInterface() throws {
        let env = try makeEnvironment()

        #expect(env["UD_WORKSPACE_NAME"] == "freek-fix-the-inbox")
        #expect(env["UD_WORKSPACE_ID"] == "w1")
        #expect(env["UD_WORKSPACE_PATH"] == "/tmp/there-fix-the-inbox")
        #expect(env["UD_PROJECT_NAME"] == "there")
        #expect(env["UD_ROOT_PATH"] == "/tmp/there")
        #expect(env["UD_DEFAULT_BRANCH"] == "main")
        #expect(env["UD_PORT"] == "3100")
        #expect(env["UD_IS_LOCAL"] == "1")

        #expect(env["UD_WORKSPACE_NAME"]?.contains("/") == false)
    }

    @Test("CONDUCTOR_ is set to exactly the same values, and nothing else is but the profile's sign-in")
    func theDeprecatedAliasMirrorsIt() throws {
        let env = try makeEnvironment()
        let login = try Store.inMemory().gitHubLogin(for: repo.profileID)
        let signedIn = login.everyVariable.merging(BitbucketCredentialHelper.variables(signedInAs: login)) { _, git in git }

        let unifieddev = env.filter { $0.key.hasPrefix("UD_") }
        let conductor = env.filter { $0.key.hasPrefix("CONDUCTOR_") }
        let rest = env.filter { !$0.key.hasPrefix("UD_") && !$0.key.hasPrefix("CONDUCTOR_") }

        #expect(unifieddev.count == conductor.count)
        #expect(rest == signedIn)
        for (key, value) in unifieddev {
            let alias = key.replacingOccurrences(of: "UD_", with: "CONDUCTOR_")
            #expect(conductor[alias] == value, "\(alias) does not mirror \(key)")
        }
    }

    @Test("the two prefixes are named apart, so a reader can tell an alias from an interface")
    func thePrefixesAreDistinguishable() {
        #expect(WorkspaceManager.environmentPrefix == "UD")
        #expect(WorkspaceManager.deprecatedEnvironmentPrefix == "CONDUCTOR")
        #expect(WorkspaceManager.environmentPrefixes == ["UD", "CONDUCTOR"])
    }

    @Test("a workspace with no port yet still gets the variable, set to zero")
    func aPortlessWorkspaceStillBindsThePort() throws {
        let env = try makeEnvironment(port: 0)
        #expect(env["UD_PORT"] == "0")
        #expect(env["CONDUCTOR_PORT"] == "0")
    }

    @Test("two projects with the same branch name are told apart by the project name")
    func theProjectNameSeparatesTwoProjectsOnTheSameBranch() throws {
        let manager = WorkspaceManager(store: try Store.inMemory())
        let names = ["/Users/freek/dev/there-there", "/Users/freek/dev/mailcoach"].map { path -> (String, String) in
            let repo = Repo(id: RepoID("r"), name: "Project", path: path, defaultBranch: "main")
            let workspace = Workspace(
                id: WorkspaceID("w"),
                repoID: repo.id,
                name: "Main",
                branch: "main",
                path: path + "-main",
                baseBranch: "main"
            )
            let env = manager.environment(for: workspace, repo: repo, port: 3_100)
            return (env["UD_WORKSPACE_NAME"] ?? "", env["UD_PROJECT_NAME"] ?? "")
        }

        #expect(names[0].0 == names[1].0)
        #expect(names[0].1 != names[1].1)
        #expect(names[0].1 == "there_there")
        #expect(names[1].1 == "mailcoach")
    }

    @Test("the project name is safe to paste into an identifier")
    func theProjectNameIsAnIdentifier() {
        let cases = [
            ("/Users/freek/dev/there-there", "there_there"),
            ("/Users/freek/dev/My Project", "My_Project"),
            ("/Users/freek/dev/laravel.dev", "laravel_dev"),
            ("/Users/freek/dev/naïve", "na_ve"),
        ]
        for (path, expected) in cases {
            let repo = Repo(id: RepoID("r"), name: "Fallback", path: path, defaultBranch: "main")
            #expect(WorkspaceManager.projectName(for: repo) == expected)
        }
    }

    @Test("a repository with no folder name falls back rather than binding an empty string")
    func aRepositoryWithNoFolderNameStillGetsAName() {
        let repo = Repo(id: RepoID("r"), name: "Rescue", path: "/", defaultBranch: "main")
        #expect(WorkspaceManager.projectName(for: repo) == "Rescue")
    }
}

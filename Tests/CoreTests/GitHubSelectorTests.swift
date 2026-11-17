import Testing
@testable import Core

@Suite("gh selectors")
struct GitHubSelectorTests {
    private var context: GitRepositoryContext {
        GitRepositoryContext.resolve(config: [
            "remote.origin.url": "git@github.com:person/project.git",
        ], base: "main", branch: "feature")
    }

    @Test("pr view with no selector is left alone")
    func viewWithoutSelector() {
        #expect(GitHub.repositoryArguments(["pr", "view", "--json", "number"], context: context)
            == ["pr", "view", "--json", "number"])
    }

    @Test("pr view with a selector still names the repository")
    func viewWithSelector() {
        #expect(GitHub.repositoryArguments(["pr", "view", "123", "--json", "number"], context: context)
            == ["pr", "view", "123", "--json", "number", "--repo", "github.com/person/project"])
        #expect(GitHub.repositoryArguments(["pr", "view", "feature"], context: context)
            == ["pr", "view", "feature", "--repo", "github.com/person/project"])
    }

    @Test("a branch tracked on a fork is named with the owner of the fork")
    func viewOfAForkedHead() {
        let forked = GitRepositoryContext.resolve(config: [
            "remote.origin.url": "git@github.com:person/project.git",
            "remote.fork.url": "git@github.com:helper/project.git",
            "branch.main.remote": "origin",
            "branch.feature.remote": "fork",
            "branch.feature.merge": "refs/heads/their/feature",
            "branch.feature.unifieddev-base-remote": "origin",
        ], base: "main", branch: "feature", baseIsBranchName: true)
        #expect(GitHub.repositoryArguments(["pr", "view", "their/feature"], context: forked)
            == ["pr", "view", "helper:their/feature", "--repo", "github.com/person/project"])
    }

    @Test("pr create names the head where the branch is published")
    func createOfAForkedHead() {
        let forked = GitRepositoryContext.resolve(config: [
            "remote.origin.url": "git@github.com:person/project.git",
            "remote.fork.url": "git@github.com:helper/project.git",
            "branch.main.remote": "origin",
            "branch.feature.remote": "fork",
            "branch.feature.merge": "refs/heads/their/feature",
            "branch.feature.unifieddev-base-remote": "origin",
        ], base: "main", branch: "feature", baseIsBranchName: true)
        #expect(GitHub.repositoryArguments(["pr", "create", "--base", "main"], context: forked)
            == [
                "pr", "create", "--base", "main", "--head", "helper:their/feature",
                "--repo", "github.com/person/project",
            ])
    }

    @Test("every other pr command still names the repository")
    func otherCommands() {
        #expect(GitHub.repositoryArguments(["pr", "list", "--json", "number"], context: context)
            == ["pr", "list", "--json", "number", "--repo", "github.com/person/project"])
        #expect(GitHub.repositoryArguments(["pr", "checkout", "123"], context: context)
            == ["pr", "checkout", "123", "--repo", "github.com/person/project"])
    }

    @Test("issue list names the repository and other issue commands are left alone")
    func issueList() {
        #expect(GitHub.repositoryArguments(["issue", "list", "--assignee", "@me"], context: context)
            == ["issue", "list", "--assignee", "@me", "--repo", "github.com/person/project"])
        #expect(GitHub.repositoryArguments(["issue", "view", "34"], context: context) == ["issue", "view", "34"])
    }
}

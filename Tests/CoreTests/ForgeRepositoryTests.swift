import Foundation
import Testing
@testable import Core

@Suite("Which host a repository lives on, read from its remote")
struct ForgeRepositoryTests {
    @Test(
        "every remote form Bitbucket Cloud hands out reads as Bitbucket",
        arguments: [
            "git@bitbucket.org:debtges/ledger.git",
            "https://kid@bitbucket.org/debtges/ledger.git",
            "https://bitbucket.org/debtges/ledger",
            "ssh://git@bitbucket.org/debtges/ledger.git",
            "https://www.bitbucket.org/debtges/ledger.git",
            "git@BitBucket.org:debtges/ledger.git",
            "git@ssh.bitbucket.org:debtges/ledger.git",
            "ssh://git@ssh.bitbucket.org/debtges/ledger.git",
        ]
    )
    func bitbucketRemotes(remote: String) throws {
        let repository = try #require(ForgeRepository.parse(remoteURL: remote))

        #expect(repository.kind == .bitbucket)
        #expect(repository.owner == "debtges")
        #expect(repository.name == "ledger")
    }

    @Test(
        "GitHub, and any host nothing claims, stay with GitHub",
        arguments: [
            "git@github.com:akira-foundation/unified-dev-swift.git",
            "https://github.com/akira-foundation/unified-dev-swift",
            "https://github.example.com/team/app.git",
            "git@bitbucket.org.example.com:team/app.git",
        ]
    )
    func gitHubRemotes(remote: String) throws {
        let repository = try #require(ForgeRepository.parse(remoteURL: remote))

        #expect(repository.kind == .gitHub)
        #expect(ForgeRepository.kind(ofRemote: remote) == .gitHub)
    }

    @Test("the host of a remote is read in every form, and a path has none")
    func hostOfRemote() {
        #expect(ForgeRepository.host(ofRemote: "git@ssh.bitbucket.org:debtges/ledger.git") == "ssh.bitbucket.org")
        #expect(ForgeRepository.host(ofRemote: "https://kid@BitBucket.org/debtges/ledger.git") == "bitbucket.org")
        #expect(ForgeRepository.host(ofRemote: "/srv/git/ledger.git") == nil)
    }

    @Test("no remote, or one with no host, is GitHub as it always was", arguments: [nil, "", "../local/repo", "/srv/git/repo.git"])
    func unreadableRemotes(remote: String?) {
        #expect(ForgeRepository.kind(ofRemote: remote) == .gitHub)
    }

    @Test("a path that is not owner and name gives no repository", arguments: [
        "https://bitbucket.org/debtges", "https://bitbucket.org/debtges/ledger/src/main", "git@bitbucket.org:-x/ledger.git",
        "git@bitbucket.org:../ledger.git", "git@bitbucket.org:debtges/...git",
    ])
    func malformedPaths(remote: String) {
        #expect(ForgeRepository.parse(remoteURL: remote) == nil)
    }

    @Test("a pull request page names its host")
    func pageNamesHost() {
        #expect(ForgeRepository.kind(ofRemote: "https://bitbucket.org/atlassian/aui/pull-requests/5486") == .bitbucket)
        #expect(ForgeRepository.kind(ofRemote: "https://github.com/acme/widgets/pull/42") == .gitHub)
    }

    @Test("a directory is judged by its base remote")
    func directoryUsesBaseRemote() async {
        let kind = await Forge.$remoteOverride.withValue({ _ in "git@bitbucket.org:debtges/ledger.git" }) {
            await Forge.kind(forDirectory: "/nowhere")
        }
        let none = await Forge.$remoteOverride.withValue({ _ in nil }) {
            await Forge.kind(forDirectory: "/nowhere")
        }

        #expect(kind == .bitbucket)
        #expect(none == .gitHub)
    }
}

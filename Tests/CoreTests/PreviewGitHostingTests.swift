import Foundation
import Testing
@testable import Core

@Suite("A preview scenario seeds the Git Hosting pane without reading this Mac")
struct PreviewGitHostingTests {
    @Test("a scenario names this Mac's account and a profile's own, and a profile it does not create is refused")
    func seeded() throws {
        let json = """
            {"projects": [{"name": "harbour"}], "profiles": [{"name": "Akira", "colour": "4C8DF6", "symbol": "leaf", "bitbucket": "own"}],
             "gitHosting": {"bitbucket": {"thisMac": "kid", "profiles": {"akira": "akira-bot"}}}}
            """
        let scenario = try PreviewScenario.read(Data(json.utf8))
        let host = try #require(scenario.gitHosting?.bitbucket)

        #expect(host.thisMacAccount == .signedIn("kid"))
        #expect(host.account(ofProfileNamed: "Akira") == .signedIn("akira-bot"))
        #expect(host.account(ofProfileNamed: "Debtges") == .signedOut)
        #expect(scenario.profiles.first?.github == .inherits)
        #expect(scenario.profiles.first?.bitbucket == .own)

        let wrong = json.replacingOccurrences(of: "\"akira\": \"akira-bot\"", with: "\"nobody\": \"x\"")
        #expect(throws: PreviewScenarioError.self) { try PreviewScenario.read(Data(wrong.utf8)) }
    }

    @Test("git hosting may name Unified and any profile in any letter case, on either host")
    func namesItKnows() throws {
        let json = """
            {"projects": [{"name": "harbour"}], "profiles": [{"name": "Akira", "colour": "4C8DF6", "symbol": "leaf"}],
             "gitHosting": {"gitHub": {"profiles": {"unified": "kid", "AKIRA": "bot"}}}}
            """
        #expect(try PreviewScenario.read(Data(json.utf8)).gitHosting?.gitHub?.account(ofProfileNamed: "Akira") == .signedIn("bot"))
        let stranger = json.replacingOccurrences(of: "\"AKIRA\"", with: "\"Nobody\"")
        #expect(throws: PreviewScenarioError.self) { try PreviewScenario.read(Data(stranger.utf8)) }
    }

    @Test("a profile with no Bitbucket choice in the scenario follows its GitHub one")
    func bitbucketFollowsGitHub() throws {
        let json = #"{"name": "Akira", "colour": "4C8DF6", "symbol": "leaf", "github": "own"}"#
        let profile = try JSONDecoder().decode(PreviewScenario.Profile.self, from: Data(json.utf8))
        #expect(profile.bitbucket == .own)
    }

    @Test("the seed is kept in the defaults and forgotten with nil")
    func adopt() {
        let (name, defaults) = TestDefaults.make("preview-git-hosting")
        defer { defaults.removePersistentDomain(forName: name) }
        PreviewScenario.GitHosting.adopt(.init(gitHub: .init(thisMac: "kid")), in: defaults)
        #expect(PreviewScenario.GitHosting.seeded(in: defaults)?.gitHub?.thisMac == "kid")
        PreviewScenario.GitHosting.adopt(nil, in: defaults)
        #expect(PreviewScenario.GitHosting.seeded(in: defaults) == nil)
    }

    @Test("the shipped scenario shows one profile on this Mac's accounts and one signed in on its own")
    func shippedScenario() throws {
        let root = URL(fileURLWithPath: #filePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let scenario = try PreviewScenario.read(path: root + "/Tools/scenarios/git-hosting.json")
        let byName = Dictionary(uniqueKeysWithValues: scenario.profiles.map { ($0.name, $0) })

        #expect(byName["Akira"]?.github == .inherits)
        #expect(byName["Akira"]?.bitbucket == .inherits)
        #expect(byName["Debtges"]?.github == .own)
        #expect(byName["Debtges"]?.bitbucket == .own)
        #expect(scenario.gitHosting?.gitHub?.account(ofProfileNamed: "Debtges") == .signedIn("debtges-bot"))
        #expect(scenario.gitHosting?.bitbucket?.thisMacAccount == .signedIn("harbour-mac"))
    }
}

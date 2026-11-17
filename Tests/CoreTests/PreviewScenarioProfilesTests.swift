import Foundation
import Testing
@testable import Core

@Suite("Seeding profiles", .tags(.git, .subprocess), .scratchDirectory, .timeLimit(.minutes(1)))
struct PreviewScenarioProfilesTests {
    private func seeder(_ name: String) throws -> PreviewScenarioSeeder {
        let root = TestScratch.unique(name)
        let manager = WorkspaceManager(
            store: try makeTestStore(name),
            workspacesRoot: URL(fileURLWithPath: root + "/workspaces", isDirectory: true)
        )
        return PreviewScenarioSeeder(manager: manager, scratchRoot: PreviewIdentity.scratch(in: root))
    }

    private func scenario() -> PreviewScenario {
        PreviewScenario(
            projects: [
                PreviewScenario.Project(name: "almanac"),
                PreviewScenario.Project(name: "ledger", profile: "Akira"),
                PreviewScenario.Project(name: "tides", profile: "Debtges"),
            ],
            profiles: [
                PreviewScenario.Profile(name: "Akira", colour: "4C8DF6", symbol: "building.2"),
                PreviewScenario.Profile(name: "Debtges", colour: "E06C2A", symbol: "briefcase", github: .own),
            ],
            activeProfile: "Akira"
        )
    }

    @Test("the scenario creates its profiles after Unified and puts each project in its own")
    func createsProfilesAndPlacesProjects() async throws {
        let seeder = try seeder("preview-profiles-placed")
        _ = try await seeder.seed(scenario())
        let store = seeder.manager.store

        let profiles = try await store.profiles()
        let placed = Dictionary(
            uniqueKeysWithValues: try await store.repos().map { ($0.name, $0.profileID) }
        )
        let byName = Dictionary(uniqueKeysWithValues: profiles.map { ($0.name, $0.id) })

        #expect(profiles.map(\.name) == ["Unified", "Akira", "Debtges"])
        #expect(placed["almanac"] == .initial)
        #expect(placed["ledger"] == byName["Akira"])
        #expect(placed["tides"] == byName["Debtges"])
        #expect(store.gitHubLogins().source(of: try #require(byName["Akira"])) == .inherits)
        #expect(store.gitHubLogins().source(of: try #require(byName["Debtges"])) == .own)
    }

    @Test("the scenario opens on the profile it names")
    func opensOnTheActiveProfile() async throws {
        let seeder = try seeder("preview-profiles-active")
        _ = try await seeder.seed(scenario())
        let store = seeder.manager.store

        let active = try await store.activeProfileID()
        let akira = try #require(try await store.profiles().first { $0.name == "Akira" })

        #expect(active == akira.id)
    }

    @Test("a scenario that names no profile leaves every project in Unified and the active profile alone")
    func absentProfileMeansUnified() async throws {
        let seeder = try seeder("preview-profiles-absent")
        _ = try await seeder.seed(PreviewScenario(projects: [PreviewScenario.Project(name: "almanac")]))
        let store = seeder.manager.store

        let placed = try await store.repos().map(\.profileID)
        let profiles = try await store.profiles().map(\.name)
        let active = try await store.activeProfileID()

        #expect(placed == [.initial])
        #expect(profiles == ["Unified"])
        #expect(active == .initial)
    }

    @Test("a project naming a profile the scenario does not declare is reported")
    func unknownProfileIsAProblem() {
        let scenario = PreviewScenario(projects: [PreviewScenario.Project(name: "ledger", profile: "Akira")])

        #expect(scenario.problems.contains { $0.contains("Akira") })
    }

    @Test("an active profile the scenario does not declare is reported")
    func unknownActiveProfileIsAProblem() {
        let scenario = PreviewScenario(
            projects: [PreviewScenario.Project(name: "ledger")],
            activeProfile: "Akira"
        )

        #expect(scenario.problems.contains { $0.contains("Akira") })
    }

    @Test("a profile declared twice, or as Unified, is reported")
    func duplicateProfilesAreProblems() {
        let scenario = PreviewScenario(
            projects: [PreviewScenario.Project(name: "ledger")],
            profiles: [
                PreviewScenario.Profile(name: "Akira", colour: "4C8DF6", symbol: "building.2"),
                PreviewScenario.Profile(name: "akira", colour: "D8608C", symbol: "briefcase"),
                PreviewScenario.Profile(name: "Unified", colour: "D8608C", symbol: "briefcase"),
            ]
        )

        #expect(scenario.problems.count == 2)
    }

    @Test("profiles and the profile of a project read from JSON, and stay optional")
    func readsFromJSON() throws {
        let read = try PreviewScenario.read(Data("""
            {"projects":[{"name":"a","profile":"Akira"},{"name":"b"}],
             "profiles":[{"name":"Akira","colour":"4C8DF6","symbol":"building.2"}],
             "activeProfile":"Akira"}
            """.utf8))
        let bare = try PreviewScenario.read(Data(#"{"projects":[{"name":"a"}]}"#.utf8))

        #expect(read.projects.map(\.profile) == ["Akira", nil])
        #expect(read.profiles == [PreviewScenario.Profile(name: "Akira", colour: "4C8DF6", symbol: "building.2")])
        #expect(read.activeProfile == "Akira")
        #expect(bare.profiles.isEmpty)
        #expect(bare.activeProfile == nil)
    }

    @Test("the shipped profiles scenario seeds three profiles with two projects each and a transcript in another one")
    func shippedScenarioSeeds() async throws {
        var scenario = try TestScenarios.shipped("profiles")
        #expect(scenario.problems.isEmpty)
        #expect(!scenario.accounts.isEmpty)
        scenario.accounts = []
        let seeder = try seeder("preview-profiles-shipped")
        _ = try await seeder.seed(scenario)
        let store = seeder.manager.store

        let profiles = try await store.profiles()
        let repos = try await store.repos()
        let active = try await store.activeProfileID()
        let counts = profiles.map { profile in repos.filter { $0.profileID == profile.id }.count }
        let elsewhere = repos.filter { $0.profileID != active }
        var chats = 0
        for repo in elsewhere {
            for workspace in try await store.workspaces(repoID: repo.id) {
                chats += try await store.sessions(workspaceID: workspace.id).count
            }
        }

        #expect(profiles.map(\.name) == ["Unified", "Akira", "Debtges"])
        #expect(counts == [2, 2, 2])
        #expect(chats > 0)
    }

    @Test("reachableProfiles opens the profiles it names and leaves the others closed")
    func opensNamedProfiles() async throws {
        let seeder = try seeder("preview-profiles-reach")
        var opened = scenario()
        opened.reachableProfiles = ["Unified", "Akira"]
        _ = try await seeder.seed(opened)
        let store = seeder.manager.store

        let byName = Dictionary(uniqueKeysWithValues: try await store.profiles().map { ($0.name, $0.id) })

        #expect(await ProfileBridgeSwitch.isOn(profile: .initial, in: store))
        #expect(await ProfileBridgeSwitch.isOn(profile: try #require(byName["Akira"]), in: store))
        #expect(await ProfileBridgeSwitch.isOn(profile: try #require(byName["Debtges"]), in: store) == false)
    }

    @Test("reachableProfiles refuses a profile the scenario does not declare")
    func refusesUnknownReachableProfile() {
        var named = scenario()
        named.reachableProfiles = ["Elsewhere"]

        #expect(named.problems.contains { $0.contains("Elsewhere") })
    }
}

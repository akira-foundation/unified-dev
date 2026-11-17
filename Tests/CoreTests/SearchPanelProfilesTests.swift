import Foundation
import Testing
@testable import Core

@Suite("Search panel profiles")
struct SearchPanelProfilesTests {
    private func profile(_ name: String, _ order: Int) -> Profile {
        Profile(
            id: ProfileID(name.lowercased()),
            name: name,
            folder: name.lowercased(),
            colour: "4C8DF6",
            symbol: "building.2",
            sortOrder: order,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private let repo = Repo(id: RepoID("repo"), name: "unifieddev", path: "/tmp/repo")

    private func workspace(_ name: String) -> Workspace {
        Workspace(
            id: WorkspaceID(name),
            repoID: repo.id,
            name: name,
            branch: "feature/x",
            path: "/tmp/\(name)",
            baseBranch: "main",
            state: .active,
            lastActivityAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func build(
        _ query: String,
        workspaces: [Workspace] = [],
        scope: HomeScope = .all,
        commands: [MenuBarItem] = [],
        profiles: [Profile],
        active: ProfileID = .initial
    ) -> SearchPanelListing {
        SearchPanelResults.build(
            query: query,
            repos: [repo],
            workspaces: workspaces,
            archived: [],
            transcripts: [],
            scope: scope,
            commands: commands,
            profiles: profiles,
            activeProfile: active
        )
    }

    private var unified: Profile { profile("Unified", 0) }
    private var foundation: Profile { profile("Foundation", 1) }
    private var folio: Profile { profile("Folio", 2) }

    @Test("a profile is found by the start of its name, under its own heading")
    func foundByName() {
        let listing = build("fo", profiles: [unified, foundation])
        let section = listing.sections.first { $0.id == "profiles" }
        #expect(section?.title == "Profiles")
        #expect(section?.rows.map(\.id) == ["profile:foundation"])
        guard case .profile(let hit) = section?.rows.first else {
            Issue.record("expected a profile row")
            return
        }
        #expect(hit.highlights == [0, 1])
    }

    @Test("the active profile is left out, because there is nothing to switch to")
    func theActiveProfileIsNotOffered() {
        let onUnified = build("nif", profiles: [unified, foundation], active: .initial)
        #expect(!onUnified.sections.contains { $0.id == "profiles" })
        #expect(onUnified.nothing != nil)

        let onFoundation = build("nif", profiles: [unified, foundation], active: foundation.id)
        #expect(onFoundation.rows.map(\.id) == ["profile:\(ProfileID.initial.rawValue)"])
        #expect(build("fo", profiles: [unified, foundation], active: foundation.id).isEmpty)
    }

    @Test("profiles appear under Everything and under no other scope")
    func onlyUnderEverything() {
        for scope in HomeScope.allCases where scope != .all {
            #expect(!build("fo", scope: scope, profiles: [foundation]).sections.contains { $0.id == "profiles" })
        }
    }

    @Test("one letter is too little to offer a profile, as with commands")
    func oneLetterIsNotEnough() {
        #expect(build("f", profiles: [foundation]).isEmpty)
    }

    @Test("the better match comes first, and a tie keeps the position in the switcher")
    func relevanceThenPosition() {
        let hits = SearchPanelProfiles.hits("fo", in: [unified, foundation, folio], active: .initial)
        #expect(hits.map(\.profile.name) == ["Folio", "Foundation"])

        let twins = [profile("Aa one", 0), profile("Aa two", 1)]
        let tied = SearchPanelProfiles.hits("aa", in: twins, active: ProfileID("none"))
        #expect(tied.map(\.profile.name) == ["Aa one", "Aa two"])
    }

    @Test("the section leads the workspaces only when its best match is at least as good")
    func theSectionFollowsRelevance() {
        let leading = build("fo", workspaces: [workspace("a long workspace with an f and an o")], profiles: [foundation])
        #expect(leading.sections.map(\.id) == ["profiles", "workspaces"])

        let tied = build("fo", workspaces: [workspace("Foundation")], profiles: [foundation])
        #expect(tied.sections.map(\.id) == ["profiles", "workspaces"])

        let trailing = build("fo", workspaces: [workspace("Fo")], profiles: [foundation])
        #expect(trailing.sections.map(\.id) == ["workspaces", "profiles"])
    }

    @Test("the section comes before the commands wherever the workspaces leave it")
    func theSectionPrecedesCommands() {
        let commands = MenuBarCatalogue.commands
        let alone = build("fo", commands: commands, profiles: [foundation])
        #expect(alone.sections.map(\.id) == ["profiles", "commands"])

        let behind = build("fo", workspaces: [workspace("Fo")], commands: commands, profiles: [foundation])
        #expect(behind.sections.map(\.id) == ["workspaces", "profiles", "commands"])
    }

    @Test("only a match counts, and it counts towards Everything whichever scope is on")
    func counted() {
        let listing = build("fo", profiles: [unified, foundation, profile("Debtges", 3)])
        #expect(listing.counts.count(of: .all, searching: true) == 1)
        #expect(listing.counts.count(of: .workspaces, searching: true) == 0)
        #expect(listing.summary == "1 result")
        #expect(listing.nothing == nil)

        let narrowed = build("fo", scope: .workspaces, profiles: [foundation])
        #expect(narrowed.counts.count(of: .all, searching: true) == 1)
    }

    @Test("a profile row cannot be pushed into")
    func notDrillable() {
        #expect(build("fo", profiles: [foundation]).rows.first?.drillable == nil)
    }

    @Test("the row names the shortcut of its position in the switcher, up to the ninth")
    func theShortcut() {
        let second = SearchPanelProfiles.hits("fo", in: [unified, foundation], active: .initial)
        #expect(second.first?.keyText == "\u{2303}\u{2318}2")

        let others = (0..<8).map { profile("Other \($0)", $0) }
        let ninth = SearchPanelProfiles.hits("fo", in: others + [foundation], active: .initial)
        #expect(ninth.first?.keyText == "\u{2303}\u{2318}9")

        let tenth = SearchPanelProfiles.hits("fo", in: others + [unified, foundation], active: ProfileID("none"))
        #expect(tenth.first { $0.profile.id == foundation.id }?.keyText == nil)
    }
}

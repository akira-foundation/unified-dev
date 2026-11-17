import Foundation
import Testing
@testable import Core

@Suite("Inspector tabs")
struct InspectorTabTests {
    private func pullRequest(checks: PullRequest.Checks, summary: String) -> PullRequest {
        PullRequest(
            number: 42,
            title: "Take the line under the greeting's button away",
            url: "https://github.com/akira-io/unifieddev/pull/42",
            state: "OPEN",
            checks: checks,
            checksSummary: summary,
            branch: "greeting-drop-footnote"
        )
    }

    @Test("no pull request means no Checks tab")
    func noPullRequest() {
        #expect(InspectorTab.available(for: nil) == [.allFiles, .changes])
    }

    @Test("a pull request GitHub has reported no runs for still means no Checks tab")
    func pullRequestWithoutChecks() {
        let none = pullRequest(checks: .none, summary: "No checks")
        #expect(InspectorTab.hasChecks(none) == false)
        #expect(InspectorTab.available(for: none) == [.allFiles, .changes])
    }

    @Test("any reported run brings the tab back", arguments: [
        PullRequest.Checks.pending, .passing, .failing,
    ])
    func pullRequestWithChecks(_ checks: PullRequest.Checks) {
        let open = pullRequest(checks: checks, summary: "12 checks passed")
        #expect(InspectorTab.hasChecks(open))
        #expect(InspectorTab.available(for: open) == [.allFiles, .changes, .checks])
    }

    @Test("a merged pull request keeps its checks, because they are still there to read")
    func mergedKeepsChecks() {
        var merged = pullRequest(checks: .passing, summary: "12 checks passed")
        merged.state = "MERGED"
        #expect(InspectorTab.available(for: merged).contains(.checks))
    }

    @Test("Checks is always the last segment")
    func checksIsLast() {
        let open = pullRequest(checks: .passing, summary: "1 check passed")
        #expect(InspectorTab.available(for: open).last == .checks)
        #expect(InspectorTab.available(for: open).prefix(2) == InspectorTab.available(for: nil).prefix(2))
    }

    @Test("a selection that is still on offer is left alone", arguments: InspectorTab.allCases)
    func selectionSurvives(_ tab: InspectorTab) {
        let open = pullRequest(checks: .failing, summary: "1 required check failed")
        #expect(InspectorTab.resolve(tab, available: InspectorTab.available(for: open, hasTasks: true, hasSideConversation: true)) == tab)
    }

    @Test("a chat with background tasks adds Tasks, before Checks")
    func tasksTab() {
        let open = pullRequest(checks: .passing, summary: "1 check passed")
        #expect(InspectorTab.available(for: nil, hasTasks: true) == [.allFiles, .changes, .tasks])
        #expect(InspectorTab.available(for: open, hasTasks: true) == [.allFiles, .changes, .tasks, .checks])
        #expect(!InspectorTab.available(for: open).contains(.tasks))
    }

    @Test("a side conversation adds Side beside Changes, before Tasks and Checks")
    func sideTab() {
        let open = pullRequest(checks: .passing, summary: "1 check passed")
        #expect(InspectorTab.available(for: nil, hasSideConversation: true) == [.allFiles, .changes, .side])
        #expect(
            InspectorTab.available(for: open, hasTasks: true, hasSideConversation: true)
                == [.allFiles, .changes, .side, .tasks, .checks]
        )
        #expect(!InspectorTab.available(for: open).contains(.side))
    }

    @Test("Tasks selected, then the chat has none, falls back to Changes")
    func tasksFallsBack() {
        #expect(InspectorTab.resolve(.tasks, available: InspectorTab.available(for: nil)) == .changes)
    }

    @Test("only the file tabs read the diff, so only they carry the scope band")
    func diffTabs() {
        #expect(InspectorTab.allCases.filter(\.readsTheDiff) == [.allFiles, .changes])
    }

    @Test("Checks selected, then the pull request goes, falls back to Changes")
    func checksFallsBack() {
        #expect(InspectorTab.resolve(.checks, available: InspectorTab.available(for: nil)) == .changes)
    }

    @Test("the choice is remembered, so the tab comes back to the reader who picked it")
    func choiceOutlivesTheGap() {
        let open = pullRequest(checks: .pending, summary: "2 checks pending")
        let chosen = InspectorTab.checks

        #expect(InspectorTab.resolve(chosen, available: InspectorTab.available(for: nil)) == .changes)
        #expect(InspectorTab.resolve(chosen, available: InspectorTab.available(for: open)) == .checks)
    }

    @Test("All files is untouched by any of this")
    func allFilesIsUnconditional() {
        #expect(InspectorTab.available(for: nil).contains(.allFiles))
        #expect(InspectorTab.resolve(.allFiles, available: InspectorTab.available(for: nil)) == .allFiles)
    }

    @Test("the fallback is one of the tabs that is always there")
    func fallbackIsAlwaysAvailable() {
        #expect(InspectorTab.available(for: nil).contains(InspectorTab.fallback))
    }
}

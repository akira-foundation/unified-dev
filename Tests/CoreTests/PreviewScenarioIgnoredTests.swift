import Foundation
import Testing
@testable import Core

@Suite("A scenario the preview did not apply")
struct PreviewScenarioIgnoredTests {
    @Test("the notice names the scenario that was ignored, the projects that are there, and the way out")
    func namesBoth() {
        let notice = PreviewScenarioIgnored.notice(
            scenarioPath: "/tmp/wt/Tools/scenarios/workspace-menu-open-in.json",
            projects: ["slipway", "harbour"]
        )

        #expect(notice.message.hasPrefix("workspace-menu-open-in.json was not applied"))
        #expect(notice.message.contains("already holds slipway and harbour."))
        #expect(notice.message.contains("`make preview-clean`"))
    }

    @Test("the notice stays until it is dismissed, because the window behind it is the wrong one")
    func staysUp() {
        let notice = PreviewScenarioIgnored.notice(scenarioPath: "/a.json", projects: ["slipway"])

        #expect(notice.dismissal == .untilDismissed)
        #expect(notice.tone == .warning)
    }

    @Test("a preview whose projects cannot be named still reads as a sentence")
    func noNames() {
        let notice = PreviewScenarioIgnored.notice(scenarioPath: "/a.json", projects: [])
        #expect(notice.message.contains("already holds projects."))
        #expect(
            PreviewScenarioError.alreadySeeded(projects: ["quay", "slipway"]).description
                == "This preview already holds quay and slipway, so the scenario was not applied again."
        )
    }

    @Test("projects are listed as a sentence would")
    func lists() {
        #expect(PreviewScenarioIgnored.listed(["slipway"]) == "slipway")
        #expect(PreviewScenarioIgnored.listed(["a", "b", "c"]) == "a, b and c")
        #expect(PreviewScenarioIgnored.listed([]) == "projects")
    }
}

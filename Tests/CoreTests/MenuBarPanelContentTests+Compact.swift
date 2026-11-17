import Foundation
import Testing
@testable import Core

extension MenuBarPanelContentTests {
    @Test("the status line says in one line who is working and whether the Mac stays awake")
    func headline() {
        let a = workspace("a")
        let b = workspace("b")
        let working = MenuBarPanelContent.make(input(
            workspaces: [a], running: [a], quotas: [calmCodex], hold: .whileAgentsRun
        ))
        #expect(working.headline == "1 agent in 1 workspace, awake")
        #expect(working.activity == .running)
        let both = MenuBarPanelContent.make(input(
            workspaces: [a, b], running: [a], waiting: [b], quotas: [calmCodex]
        ))
        #expect(both.headline == "1 agent in 1 workspace, 1 waiting on you")
        let waiting = MenuBarPanelContent.make(input(workspaces: [b], waiting: [b], quotas: [calmCodex]))
        #expect(waiting.activity == .waiting)
        let idle = MenuBarPanelContent.make(input(quotas: [calmCodex]))
        #expect(idle.headline == "No agents running")
        #expect(idle.activity == .idle)
    }

    @Test("a provider with more than three limits always shown folds the rest away")
    func foldingBeyondThree() {
        let limits = ["opus", "sonnet", "haiku", "fable"].map {
            quota(.claudeCode, QuotaWindow(key: "seven_day_model_\($0)", label: "Week (\($0))", duration: 604_800), 0.1)
        }
        let content = MenuBarPanelContent.make(input(quotas: limits))
        #expect(content.providers.first?.section?.onDemand.isEmpty == true)
        #expect(content.providers.first?.isFoldable == true)
    }

    @Test("the status line in the cases with nobody running")
    func headlineCorners() {
        #expect(MenuBarPanelContent.headline(running: 2, workspaces: 0, waiting: 0, hold: .none) == "2 agents running")
        #expect(MenuBarPanelContent.headline(running: 0, workspaces: 0, waiting: 2, hold: .none) == "2 waiting on you")
        #expect(MenuBarPanelContent.headline(running: 0, workspaces: 0, waiting: 0, hold: .indefinitely) == "No agents running, awake")
        let elsewhere = MenuBarPanelContent.headline(
            running: 0, workspaces: 0, waiting: 0, hold: .whileAgentsRun, hasAgentsElsewhere: true
        )
        #expect(elsewhere == "No agents in this profile, awake")
    }

    @Test("an agent running outranks one waiting in the status dot")
    func activityOrder() {
        let a = workspace("a")
        let b = workspace("b")
        let both = MenuBarPanelContent.make(input(workspaces: [a, b], running: [a], waiting: [b], quotas: [calmCodex]))
        #expect(both.activity == .running)
    }
}

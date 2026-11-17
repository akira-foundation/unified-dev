import Testing
import Foundation
@testable import Core

@Suite("Notification inbox scenario")
struct NotificationInboxScenarioTests {
    private let project = PreviewScenario.Project(
        name: "ledger",
        workspaces: [PreviewScenario.Workspace(
            name: "Close", branch: "close",
            chats: [PreviewScenario.Chat(title: "Chat", messages: [])]
        )]
    )

    @Test("a notification that names what the scenario declares is accepted")
    func accepted() {
        let scenario = PreviewScenario(projects: [project], notifications: [
            .init(event: .needsInput, project: "ledger", workspace: "Close", chat: "Chat"),
            .init(event: .setupFailed, project: "ledger", workspace: "Anything", removed: true),
        ])

        #expect(scenario.notificationProblems.isEmpty)
    }

    @Test("a notification that names what is not declared is refused", arguments: [
        PreviewScenario.SeededNotification(event: .needsInput, project: "nope", workspace: "Close"),
        PreviewScenario.SeededNotification(event: .needsInput, project: "ledger", workspace: "nope"),
        PreviewScenario.SeededNotification(event: .needsInput, project: "ledger", workspace: "Close", chat: "nope"),
    ])
    func refused(notification: PreviewScenario.SeededNotification) {
        let scenario = PreviewScenario(projects: [project], notifications: [notification])

        #expect(scenario.notificationProblems.count == 1)
    }

    @Test("the fields of a seeded notification default when absent")
    func decodesDefaults() throws {
        let json = #"{"event":"turnFinished","project":"ledger","workspace":"Close"}"#

        let decoded = try JSONDecoder().decode(PreviewScenario.SeededNotification.self, from: Data(json.utf8))

        #expect(decoded == .init(event: .turnFinished, project: "ledger", workspace: "Close"))
    }
}

@Suite("Seeding notifications", .tags(.git, .subprocess), .scratchDirectory, .timeLimit(.minutes(1)))
struct PreviewScenarioNotificationSeedingTests {
    private func seeder() throws -> PreviewScenarioSeeder {
        let root = TestScratch.unique("preview-notifications")
        let manager = WorkspaceManager(
            store: try makeTestStore("preview-notifications"),
            workspacesRoot: URL(fileURLWithPath: root + "/workspaces", isDirectory: true)
        )
        return PreviewScenarioSeeder(manager: manager, scratchRoot: PreviewIdentity.scratch(in: root))
    }

    @Test("the shipped profiles scenario seeds the bell, and read is per row")
    func shippedScenarioSeeds() async throws {
        var scenario = try TestScenarios.shipped("profiles")
        #expect(scenario.problems.isEmpty)
        scenario.accounts = []
        let seeder = try seeder()

        let outcome = try await seeder.seed(scenario)

        let rows = try await seeder.manager.store.inboxNotifications()
        #expect(outcome.notifications == scenario.notifications.count)
        #expect(rows.count == scenario.notifications.count)
        #expect(rows.filter(\.isRead).map(\.event) == [.checksFinished])
        #expect(rows.first { $0.event == .setupFailed }?.destination == .gone)
        #expect(rows.first { $0.event == .agentFailed }?.workspaceState == .archived)
        #expect(NotificationInbox.unseenCount(rows) == 4)
    }

    @Test("a scenario reads its notifications and refuses one that names nothing it declares")
    func scenarioReadsAndValidates() throws {
        let read = try PreviewScenario.read(Data(#"""
        {"projects":[{"name":"ledger","workspaces":[{"name":"Close","branch":"close"}]}],
         "notifications":[{"event":"needsInput","project":"ledger","workspace":"Close"}]}
        """#.utf8))

        #expect(read.notifications.map(\.workspace) == ["Close"])
        #expect(throws: (any Error).self) {
            try PreviewScenario.read(Data(#"""
            {"projects":[{"name":"ledger"}],
             "notifications":[{"event":"needsInput","project":"ghost","workspace":"Close"}]}
            """#.utf8))
        }
    }
}

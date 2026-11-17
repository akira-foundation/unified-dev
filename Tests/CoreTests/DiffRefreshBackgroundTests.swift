import Foundation
import Testing
@testable import Core

@Suite("What the diff stat poll reads behind another app")
struct DiffRefreshBackgroundTests {
    private func ids(_ count: Int) -> [WorkspaceID] {
        (0..<count).map { WorkspaceID("w\($0)") }
    }

    private func justRefreshed(_ ids: [WorkspaceID], at moment: Date) -> [WorkspaceID: Date] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, moment) })
    }

    @Test("behind another app only the workspace on screen is asked about")
    func backgroundReadsTheSelectedOneAlone() {
        let all = ids(20)
        let now = Date()
        let busy: Set<WorkspaceID> = [all[3], all[7], all[11]]
        let last = justRefreshed(all, at: now.addingTimeInterval(-DiffRefreshSchedule.busyShownMaxAge))

        let front = DiffRefreshSchedule.due(
            workspaces: all, busy: busy, selected: all[5], lastRefreshed: last, now: now
        )
        let behind = DiffRefreshSchedule.due(
            workspaces: all,
            busy: busy,
            selected: all[5],
            activity: .background,
            lastRefreshed: last,
            now: now
        )

        #expect(front.count == 3)
        #expect(behind == [all[5]])
    }

    @Test("behind another app with nothing on screen git is asked nothing")
    func backgroundWithNoSelection() {
        let all = ids(20)
        let now = Date()

        let due = DiffRefreshSchedule.due(
            workspaces: all,
            busy: [all[2]],
            activity: .background,
            lastRefreshed: [:],
            now: now
        )

        #expect(due.isEmpty)
    }

    @Test("behind another app a selection that has left the sidebar is not read")
    func backgroundWithASelectionThatIsGone() {
        let all = ids(5)

        let due = DiffRefreshSchedule.due(
            workspaces: all,
            busy: [],
            selected: WorkspaceID("archived"),
            activity: .background,
            lastRefreshed: [:],
            now: Date()
        )

        #expect(due.isEmpty)
    }

    @Test("behind another app the trickle of idle workspaces stops")
    func backgroundHasNoTrickle() {
        let all = ids(20)
        let now = Date()
        let last = justRefreshed(all, at: now.addingTimeInterval(-DiffRefreshSchedule.idleMaxAge * 2))

        let due = DiffRefreshSchedule.due(
            workspaces: all,
            busy: [],
            selected: all[0],
            activity: .background,
            lastRefreshed: last,
            now: now
        )

        #expect(due == [all[0]])
    }

    @Test("behind another app nothing new is asked about either")
    func backgroundIgnoresWorkspacesNeverAskedAbout() {
        let all = ids(20)

        let due = DiffRefreshSchedule.due(
            workspaces: all,
            busy: [],
            selected: all[9],
            activity: .background,
            lastRefreshed: [:],
            now: Date()
        )

        #expect(due == [all[9]])
    }
}

import Foundation
import Testing
@testable import Core

@Suite("How often a busy workspace is read, by where it is")
struct DiffRefreshBusyCadenceTests {
    private let selected = WorkspaceID("selected")
    private let shown = WorkspaceID("shown")
    private let hidden = WorkspaceID("hidden")

    private func due(readSecondsAgo age: TimeInterval, failures: [WorkspaceID: DiffRefreshSchedule.Failure] = [:]) -> [WorkspaceID] {
        let now = Date()
        let all = [selected, shown, hidden]
        return DiffRefreshSchedule.due(
            workspaces: all,
            busy: Set(all),
            selected: selected,
            shown: [selected, shown],
            failures: failures,
            lastRefreshed: Dictionary(uniqueKeysWithValues: all.map { ($0, now.addingTimeInterval(-age)) }),
            now: now
        )
    }

    @Test("one tick later only the selected workspace is read again")
    func oneTick() {
        #expect(due(readSecondsAgo: DiffRefreshSchedule.tick) == [selected])
    }

    @Test("two ticks later the busy workspaces in the sidebar are read too")
    func twoTicks() {
        #expect(due(readSecondsAgo: DiffRefreshSchedule.tick * 2) == [selected, shown])
    }

    @Test("a busy workspace in a profile not on screen waits for its own longer age")
    func otherProfile() {
        #expect(!due(readSecondsAgo: DiffRefreshSchedule.tick * 4).contains(hidden))
        #expect(due(readSecondsAgo: DiffRefreshSchedule.busyHiddenMaxAge) == [selected, shown, hidden])
    }

    @Test("with no list of what is shown every busy workspace counts as shown")
    func noShownListMeansShown() {
        let now = Date()
        let due = DiffRefreshSchedule.due(
            workspaces: [hidden], busy: [hidden],
            lastRefreshed: [hidden: now.addingTimeInterval(-DiffRefreshSchedule.busyShownMaxAge)], now: now
        )

        #expect(due == [hidden])
    }

    @Test("a workspace whose last read failed waits out a growing delay")
    func failureBacksOff() {
        let now = Date()
        let failed = DiffRefreshSchedule.Failure(count: 1, at: now.addingTimeInterval(-DiffRefreshSchedule.tick))
        let failedTwice = DiffRefreshSchedule.Failure(
            count: 2, at: now.addingTimeInterval(-DiffRefreshSchedule.tick * 2)
        )

        #expect(due(readSecondsAgo: 60, failures: [selected: failed]) == [shown, hidden])
        #expect(due(readSecondsAgo: 60, failures: [selected: failedTwice]) == [shown, hidden])
    }

    @Test("once the delay has passed the failed workspace is tried again")
    func failureRetriesAfterDelay() {
        let now = Date()
        let failed = DiffRefreshSchedule.Failure(
            count: 1, at: now.addingTimeInterval(-DiffRefreshSchedule.retryDelay(afterFailures: 1))
        )

        #expect(due(readSecondsAgo: 60, failures: [selected: failed]) == [selected, shown, hidden])
    }

    @Test("the delay doubles and stops at the ceiling", arguments: [
        (1, DiffRefreshSchedule.tick * 2),
        (2, DiffRefreshSchedule.tick * 4),
        (3, DiffRefreshSchedule.tick * 8),
        (4, DiffRefreshSchedule.failureBackoffCeiling),
        (40, DiffRefreshSchedule.failureBackoffCeiling),
    ])
    func delayGrows(failures: Int, delay: TimeInterval) {
        #expect(DiffRefreshSchedule.retryDelay(afterFailures: failures) == delay)
    }

    @Test("behind another app a failing selection is not retried every tick either")
    func backgroundBacksOff() {
        let now = Date()
        let failed = DiffRefreshSchedule.Failure(count: 1, at: now.addingTimeInterval(-DiffRefreshSchedule.backgroundTick))

        let due = DiffRefreshSchedule.due(
            workspaces: [selected], busy: [selected], selected: selected, activity: .background,
            failures: [selected: failed], lastRefreshed: [:], now: now
        )

        #expect(due.isEmpty)
    }

    @Test("a further failure counts one more and moves the clock")
    func failureAccumulates() {
        let first = DiffRefreshSchedule.Failure(count: 1, at: Date(timeIntervalSince1970: 0))
        let later = Date(timeIntervalSince1970: 100)

        #expect(first.after(another: later) == DiffRefreshSchedule.Failure(count: 2, at: later))
    }
}

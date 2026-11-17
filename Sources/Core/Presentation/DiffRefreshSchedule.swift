import Foundation

public enum DiffRefreshSchedule {
    public enum Activity: Sendable, Equatable {
        case foreground
        case background
    }

    public static let tick: TimeInterval = 6

    public static let backgroundTick: TimeInterval = 30

    public static let width = 4

    public static let idleMaxAge: TimeInterval = 300

    public static let selectedMaxAge: TimeInterval = 30

    public static let busyShownMaxAge: TimeInterval = 12

    public static let busyHiddenMaxAge: TimeInterval = 30

    public static let failureBackoffCeiling: TimeInterval = 60

    public struct Failure: Sendable, Equatable {
        public var count: Int
        public var at: Date

        public init(count: Int, at: Date) {
            self.count = count
            self.at = at
        }

        public func after(another moment: Date) -> Failure {
            Failure(count: count + 1, at: moment)
        }
    }

    public static func retryDelay(afterFailures count: Int, tick: TimeInterval = tick) -> TimeInterval {
        guard count > 0 else { return 0 }
        return min(tick * pow(2, Double(min(count, 16))), failureBackoffCeiling)
    }

    static func isBackingOff(_ failure: Failure?, now: Date, tick: TimeInterval) -> Bool {
        guard let failure else { return false }
        return now.timeIntervalSince(failure.at) + tick / 2 < retryDelay(afterFailures: failure.count, tick: tick)
    }

    static func busyMaxAge(_ id: WorkspaceID, selected: WorkspaceID?, shown: Set<WorkspaceID>?) -> TimeInterval {
        if id == selected { return 0 }
        guard let shown, !shown.contains(id) else { return busyShownMaxAge }
        return busyHiddenMaxAge
    }

    public static func tick(for activity: Activity) -> TimeInterval {
        switch activity {
        case .foreground: tick
        case .background: backgroundTick
        }
    }

    public static func priority(for activity: Activity) -> TaskPriority {
        switch activity {
        case .foreground: .userInitiated
        case .background: .utility
        }
    }

    public static func isDue(
        activity: Activity, lastRun: ContinuousClock.Instant?, now: ContinuousClock.Instant
    ) -> Bool {
        guard let lastRun else { return true }
        return now - lastRun >= .seconds(tick(for: activity))
    }

    public static func due(
        workspaces: [WorkspaceID],
        busy: Set<WorkspaceID>,
        selected: WorkspaceID? = nil,
        activity: Activity = .foreground,
        shown: Set<WorkspaceID>? = nil,
        failures: [WorkspaceID: Failure] = [:],
        lastRefreshed: [WorkspaceID: Date],
        now: Date,
        tick: TimeInterval = tick,
        idleMaxAge: TimeInterval = idleMaxAge,
        selectedMaxAge: TimeInterval = selectedMaxAge
    ) -> [WorkspaceID] {
        if activity == .background {
            guard let selected, workspaces.contains(selected),
                  !isBackingOff(failures[selected], now: now, tick: backgroundTick) else { return [] }
            return [selected]
        }

        var due: [WorkspaceID] = []
        var stale: [(id: WorkspaceID, age: TimeInterval, place: Int)] = []

        for (place, id) in workspaces.enumerated() {
            guard !isBackingOff(failures[id], now: now, tick: tick) else { continue }
            if busy.contains(id) {
                let age = lastRefreshed[id].map { now.timeIntervalSince($0) } ?? .infinity
                if age + tick / 2 >= busyMaxAge(id, selected: selected, shown: shown) { due.append(id) }
                continue
            }
            guard let last = lastRefreshed[id] else {
                due.append(id)
                continue
            }
            let age = now.timeIntervalSince(last)
            if id == selected {
                if age >= selectedMaxAge { due.append(id) }
                continue
            }
            guard age >= idleMaxAge else { continue }
            stale.append((id, age, place))
        }

        guard !stale.isEmpty else { return due }

        let idleCount = workspaces.count { !busy.contains($0) && $0 != selected }
        let perTick = max(1, Int((Double(idleCount) * tick / idleMaxAge).rounded(.up)))

        let oldest = stale
            .sorted { $0.age == $1.age ? $0.place < $1.place : $0.age > $1.age }
            .prefix(perTick)
        due.append(contentsOf: oldest.map(\.id))
        return due
    }
}

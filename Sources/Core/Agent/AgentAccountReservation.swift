import Foundation

public struct AgentAccountReservation: Sendable, Hashable {
    public let plan: AgentAccountCreation
    private let support: URL

    init(plan: AgentAccountCreation, support: URL) {
        self.plan = plan
        self.support = support
    }

    @discardableResult
    public func discard(processes: () -> [ProcessVector]? = ProcessVectors.ofOtherProcesses) -> Bool {
        guard plan.directoryExists,
              let directory = AgentAccountRemoval.directory(of: plan.home, support: support),
              AgentAccountFolderUse.of(directory, among: processes()) == .free else { return false }
        return (try? FileManager.default.removeItem(at: directory)) != nil
    }

    @discardableResult
    public func discardOnceReleased(
        attempts: Int = 20,
        pause: Duration = .milliseconds(250),
        processes: @Sendable () -> [ProcessVector]? = ProcessVectors.ofOtherProcesses
    ) async -> Bool {
        guard AgentAccountRemoval.directory(of: plan.home, support: support) != nil else { return false }
        for attempt in 0..<attempts {
            if attempt > 0 { try? await Task.sleep(for: pause) }
            guard plan.directoryExists else { return false }
            if discard(processes: processes) { return true }
        }
        return false
    }
}

extension AgentAccountCreation {
    public static func reserve(
        provider: AgentKind,
        label: String,
        existing: [AgentAccountID],
        support: URL,
        discriminant: String = freshDiscriminant()
    ) throws -> AgentAccountReservation {
        let made = plan(
            provider: provider,
            label: label,
            existing: existing + occupiedIDs(support: support),
            support: support,
            discriminant: discriminant
        )
        guard !made.directoryExists else { throw AgentAccountError.folderAlreadyThere(made.directory.path) }
        try prepareDirectory(of: made.home)
        return AgentAccountReservation(plan: made, support: support)
    }
}

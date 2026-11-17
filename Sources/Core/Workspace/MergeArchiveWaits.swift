import Foundation

public struct MergeArchiveWaits: Sendable, Equatable {
    public enum Settlement: Sendable, Equatable {
        case notWaiting
        case keepWaiting
        case archive(pullRequest: Int)
        case dropStopped
    }

    public static let recheckInterval = Duration.seconds(15)

    public private(set) var pullRequests: [WorkspaceID: Int] = [:]
    public private(set) var recheckedIDs: Set<WorkspaceID> = []
    public private(set) var mergedHeads: [WorkspaceID: String] = [:]
    private var announcedIDs: Set<WorkspaceID> = []

    public init() {}

    public var ids: Set<WorkspaceID> { Set(pullRequests.keys) }

    public mutating func wait(for id: WorkspaceID, pullRequest: Int) {
        pullRequests[id] = pullRequest
    }

    public mutating func forget(_ id: WorkspaceID) {
        pullRequests[id] = nil
        mergedHeads[id] = nil
        recheckedIDs.remove(id)
        announcedIDs.remove(id)
    }

    @discardableResult
    public mutating func record(
        _ decision: MergeArchiveDecision, for id: WorkspaceID, pullRequest: Int, mergedHead: String? = nil
    ) -> Bool {
        if decision == .archiveAfterTurn || decision == .waitForCommand { mergedHeads[id] = mergedHead }
        switch decision {
        case .archiveAfterTurn:
            wait(for: id, pullRequest: pullRequest)
            return false
        case .waitForCommand:
            wait(for: id, pullRequest: pullRequest)
            recheckedIDs.insert(id)
            return announcedIDs.insert(id).inserted
        case .archiveNow, .forget:
            forget(id)
            return false
        case .leave:
            return false
        }
    }

    public mutating func settle(
        _ id: WorkspaceID, isAgentMidTurn: Bool, isCommandRunning: Bool, wasStopped: Bool
    ) -> Settlement {
        guard let pullRequest = pullRequests[id] else { return .notWaiting }
        if wasStopped {
            forget(id)
            return .dropStopped
        }
        guard !isAgentMidTurn else { return .keepWaiting }
        guard !isCommandRunning else {
            recheckedIDs.insert(id)
            return .keepWaiting
        }
        forget(id)
        return .archive(pullRequest: pullRequest)
    }
}

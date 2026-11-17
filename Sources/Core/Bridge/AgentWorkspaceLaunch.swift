import Foundation

public enum LaunchRetry: Sendable, Equatable {
    case whenAWorkspaceIsArchived(limit: Int)
    case after(Date)
}

public enum LaunchRefusal: Sendable, Equatable {
    case unavailable(String)
    case overAllowance(String, retry: LaunchRetry)
    case failed(String)

    public var sentence: String {
        switch self {
        case .unavailable(let sentence), .overAllowance(let sentence, _), .failed(let sentence): sentence
        }
    }
}

public struct AgentWorkspaceLaunch: Sendable {
    public enum Outcome: Sendable, Equatable {
        case started(StartedWorkspaceSummary)
        case alreadyStarted(Workspace)
        case refused(LaunchRefusal)
    }

    private let start: WorkspaceStarting

    public init(start: @escaping WorkspaceStarting) {
        self.start = start
    }

    public func launch(
        _ order: AgentWorkspaceOrder,
        in project: Repo,
        as identity: BridgeIdentity,
        origin: WorkspaceOrigin,
        store: Store,
        now: Date = Date()
    ) async -> Outcome {
        if let spawnID = origin.spawnToolUseID {
            do {
                let existing = try await store.workspaces(spawnToolUseID: spawnID).first { $0.state != .archived }
                if let existing { return .alreadyStarted(existing) }
            } catch {
                return .refused(.unavailable(
                    "Unified Dev could not check for a repeat of this call: \(error.readableMessage)"
                ))
            }
        }

        do {
            if let refusal = try await Self.overAllowance(origin, store: store, now: now) {
                return .refused(refusal)
            }
        } catch {
            return .refused(.unavailable(
                "Unified Dev could not check how many workspaces it has started recently: "
                    + error.readableMessage
            ))
        }

        do {
            return .started(try await start(order, project, identity, origin))
        } catch {
            let trouble = await WorkspaceStartTrouble.diagnose(
                error,
                project: project.name,
                projectPath: project.path,
                baseBranch: order.source.namedBranch ?? project.defaultBranch,
                wasRequested: order.source.namedBranch != nil
            )
            return .refused(.failed(trouble.sentence))
        }
    }

    static func overAllowance(
        _ origin: WorkspaceOrigin, store: Store, now: Date
    ) async throws -> LaunchRefusal? {
        let allowance = WorkspaceStartAllowance.of(origin, parent: try await parentRow(of: origin, store: store))

        switch allowance {
        case .unlimited:
            return nil

        case .running(let limit):
            guard let parent = origin.parentWorkspaceID else { return nil }
            let live = try await store.workspaces(startedBy: parent)
            return allowance.refusal(count: live.count).map {
                .overAllowance($0, retry: .whenAWorkspaceIsArchived(limit: limit))
            }

        case .rate(_, let window):
            let recent = try await store.workspacesStartedByOwnerClient(since: now.addingTimeInterval(-window))
            let freed = (recent.map(\.createdAt).min() ?? now).addingTimeInterval(window)
            return allowance.refusal(count: recent.count).map { .overAllowance($0, retry: .after(freed)) }
        }
    }

    private static func parentRow(of origin: WorkspaceOrigin, store: Store) async throws -> Workspace? {
        guard let parent = origin.parentWorkspaceID else { return nil }
        return try await store.workspace(id: parent)
    }
}

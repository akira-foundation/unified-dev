import Foundation

public enum BridgeWorkspaceLookup: Sendable {
    public enum Outcome: Sendable, Equatable {
        case found(Workspace)
        case unknown
        case ambiguous([Workspace])
    }

    public static func find(_ query: String, among workspaces: [Workspace]) -> Outcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        if let byID = workspaces.first(where: {
            $0.id.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return .found(byID)
        }

        let byName = workspaces.filter { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        switch byName.count {
        case 0: return .unknown
        case 1: return .found(byName[0])
        default: return .ambiguous(byName)
        }
    }

    public enum ActiveTarget: Sendable, Equatable {
        case found(Workspace)
        case ambiguous(ids: [String])
        case archived(name: String)
        case unknown(known: [String])
    }

    static func activeTarget(
        _ given: String, as identity: BridgeIdentity, store: Store
    ) async throws -> ActiveTarget {
        let all = try await BridgeProfileScope.workspaces(for: identity, store: store, includeArchived: true)
        return activeTarget(given, among: all, label: \.name)
    }

    static func activeTarget(_ given: String, in profile: Profile, store: Store) async throws -> ActiveTarget {
        let all = ProfileScope.workspaces(
            try await store.workspaces(includeArchived: true), repos: try await store.repos(), in: profile.id
        )
        return activeTarget(given, among: all, label: \.id.rawValue)
    }

    private static func activeTarget(
        _ given: String, among all: [Workspace], label: KeyPath<Workspace, String>
    ) -> ActiveTarget {
        let active = all.filter { $0.state != .archived }
        switch find(given, among: active) {
        case .found(let workspace):
            return .found(workspace)
        case .ambiguous(let matches):
            return .ambiguous(ids: matches.map(\.id.rawValue))
        case .unknown:
            if case .found(let archived) = find(given, among: all) { return .archived(name: archived[keyPath: label]) }
            return .unknown(known: active.map { $0[keyPath: label] })
        }
    }

    static func unknown(_ given: String, known: [String]) -> String {
        """
        Unified Dev has no active workspace called '\(given)'. Active workspaces: \
        \(list(known)). Retrying with the same name will fail the same way, so pass an id \
        workspace_list reports.
        """
    }

    static func ambiguous(_ given: String, ids: [String]) -> String {
        """
        More than one workspace is called '\(given)', so Unified Dev will not guess which you \
        meant. Pass one of these ids instead: \(list(ids)).
        """
    }

    static let listLimit = 10

    static func list(_ names: [String]) -> String {
        guard !names.isEmpty else { return "nothing" }
        let shown = names.prefix(listLimit).map(WorkspaceMessage.oneLine).joined(separator: ", ")
        let rest = names.count - listLimit
        return rest > 0 ? shown + " and \(rest) more" : shown
    }
}

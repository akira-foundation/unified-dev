import Foundation

public struct SearchPanelScopeSegment: Equatable, Sendable, Identifiable {
    public var scope: HomeScope
    public var name: String
    public var count: Int

    public var id: HomeScope { scope }

    public var title: String { "\(name) (\(count))" }

    public static func offered(counts: HomeScopeCounts) -> [SearchPanelScopeSegment] {
        HomeScope.offered(searching: true).map { scope in
            SearchPanelScopeSegment(
                scope: scope,
                name: scope.label(searching: true),
                count: counts.count(of: scope, searching: true)
            )
        }
    }
}

import Foundation

public struct UsageCompactSection: Sendable, Hashable {
    public static let visibleLimit = 3

    public var rows: [UsageCompactRow]
    public var folded: [String]
    public var summary: String?
    public var isExpanded: Bool

    public var isFoldable: Bool { !folded.isEmpty }

    public var foldTitle: String {
        isExpanded ? "Show less" : MenuBarPanelContent.moreTitle(folded.count)
    }

    public var foldSpoken: String {
        isExpanded ? "Show fewer limits" : "Show \(Counted.of(folded.count, "more limit"))"
    }

    public var foldedNames: String? {
        isExpanded || folded.isEmpty ? nil : folded.joined(separator: ", ")
    }

    public static func make(
        _ section: UsageLayout.Section,
        at now: Date,
        options: UsageDisplayOptions
    ) -> UsageCompactSection {
        let selection = select(section)
        let drawn = section.isExpanded ? selection.all : selection.shown
        return UsageCompactSection(
            rows: drawn.compactMap { UsageCompactRow.of($0, at: now, options: options) },
            folded: selection.folded.map(\.title),
            summary: summary(of: section.alwaysVisible + section.onDemand),
            isExpanded: section.isExpanded
        )
    }

    public static func foldCount(_ section: UsageLayout.Section) -> Int {
        select(section).folded.count
    }

    static func select(
        _ section: UsageLayout.Section
    ) -> (all: [UsageMetric], shown: [UsageMetric], folded: [UsageMetric]) {
        let all = byShare((section.alwaysVisible + section.onDemand).filter { $0.quota != nil })
        let always = section.alwaysVisible.filter { $0.quota != nil }
        let candidates = byShare(always.isEmpty ? all : always)
        let kept = Set(candidates.prefix(visibleLimit).map(\.id))
        return (all, all.filter { kept.contains($0.id) }, all.filter { !kept.contains($0.id) })
    }

    static func byShare(_ metrics: [UsageMetric]) -> [UsageMetric] {
        metrics.enumerated()
            .sorted { lhs, rhs in
                let left = share(lhs.element), right = share(rhs.element)
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
    }

    static func share(_ metric: UsageMetric) -> Double {
        guard let quota = metric.quota, let (used, limit) = UsageMeterReading.figures(quota), limit > 0 else {
            return -1
        }
        return used / limit
    }

    static func summary(of metrics: [UsageMetric]) -> String? {
        let parts = metrics.compactMap(\.headerPhrase)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

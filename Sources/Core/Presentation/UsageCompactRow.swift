import Foundation

public struct UsageCompactRow: Sendable, Hashable, Identifiable {
    public var id: UsageMetricID
    public var title: String
    public var reading: UsageMeterReading
    public var value: String
    public var reset: String
    public var alert: String?
    public var showsFlame: Bool

    public var resetHelp: String? { reading.trailing.isEmpty || reading.trailing == reset ? nil : reading.trailing }
    public var alertHelp: String? { reading.status?.text ?? reading.status?.tooltip }
    public var spoken: String { reading.spoken(title: title) }

    public static func of(_ metric: UsageMetric, at now: Date, options: UsageDisplayOptions) -> UsageCompactRow? {
        guard let quota = metric.quota else { return nil }
        let reading = UsageMeterReading.of(quota, isSession: metric.isSession, at: now, options: options)
        let deadline = reading.status?.deadline
        return UsageCompactRow(
            id: metric.id,
            title: metric.title,
            reading: reading,
            value: reading.menuBarValue ?? UsageMeterReading.emptyHeadline,
            reset: quota.resetsAt.map { UsageFormat.countdown(until: $0, from: now) } ?? reading.trailing,
            alert: deadline.map { UsageFormat.countdown(until: $0, from: now) },
            showsFlame: reading.status?.showsFlame ?? false
        )
    }
}

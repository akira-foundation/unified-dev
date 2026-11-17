import Foundation

public enum AgentAccountNames {
    public static let defaultTitle = "Default account"

    public struct Entry: Sendable, Hashable {
        public let home: AgentAccountHome
        public let identity: AgentAccountIdentity?

        public init(home: AgentAccountHome, identity: AgentAccountIdentity?) {
            self.home = home
            self.identity = identity
        }
    }

    public static func title(of entry: Entry, among entries: [Entry]) -> String {
        let name = base(of: entry)
        let twins = entries.filter {
            $0.home.provider == entry.home.provider && base(of: $0) == name
        }
        guard twins.count > 1 else { return name }
        let qualifier = entry.home.isDefault ? "default" : entry.home.directory.lastPathComponent
        return "\(name) (\(qualifier))"
    }

    public static func title(
        of standing: AgentAccountStanding,
        among standings: [AgentAccountStanding]
    ) -> String {
        title(of: entry(standing), among: standings.map(entry))
    }

    public static func title(of home: AgentAccountHome, among standings: [AgentAccountStanding]) -> String? {
        standings.first { $0.home.id == home.id && $0.home.provider == home.provider }
            .map { title(of: $0, among: standings) }
    }

    public static func spoken(of home: AgentAccountHome, among standings: [AgentAccountStanding]) -> String {
        if isGenericDefault(home, among: standings) { return "the default account" }
        return title(of: home, among: standings) ?? home.directory.lastPathComponent
    }

    public static func isGenericDefault(_ standing: AgentAccountStanding) -> Bool {
        isGenericDefault(entry(standing))
    }

    public static func isGenericDefault(_ home: AgentAccountHome, among standings: [AgentAccountStanding]) -> Bool {
        standings.first { $0.home.id == home.id && $0.home.provider == home.provider }
            .map(isGenericDefault) ?? false
    }

    public static func reference(to standing: AgentAccountStanding, among standings: [AgentAccountStanding]) -> String {
        isGenericDefault(standing) ? "the default account" : title(of: standing, among: standings)
    }

    static func isGenericDefault(_ entry: Entry) -> Bool {
        entry.home.isDefault && email(of: entry) == nil
    }

    static func base(of entry: Entry) -> String {
        if let email = email(of: entry) { return email }
        if entry.home.isDefault { return defaultTitle }
        return entry.home.label.isEmpty ? entry.home.directory.lastPathComponent : entry.home.label
    }

    private static func email(of entry: Entry) -> String? {
        guard let email = entry.identity?.email, !email.isEmpty else { return nil }
        return email
    }

    private static func entry(_ standing: AgentAccountStanding) -> Entry {
        Entry(home: standing.home, identity: standing.identity)
    }
}

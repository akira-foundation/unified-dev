import Foundation

public struct AgentAccountPage: Sendable, Equatable {
    public static let listTitle = "Accounts"

    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: AgentAccountID
        public let title: String
        public let detail: String
        public let warns: Bool
    }

    public enum Section: Sendable, Equatable, Identifiable {
        case list
        case account(AgentAccountPanel.Row)

        public var id: String {
            switch self {
            case .list: "list"
            case .account(let row): "account:\(row.id.rawValue)"
            }
        }
    }

    public let entries: [Entry]
    public let offer: AgentAccountOffer
    public let sections: [Section]
    public let listFooter: String?
    public static func make(_ panel: AgentAccountPanel) -> AgentAccountPage {
        AgentAccountPage(
            entries: panel.rows.map(entry),
            offer: panel.offer,
            sections: [.list] + panel.rows.map(Section.account),
            listFooter: listFooter(of: panel)
        )
    }

    private static func entry(for row: AgentAccountPanel.Row) -> Entry {
        Entry(
            id: row.id,
            title: row.title,
            detail: row.session,
            warns: row.sessionWarns
        )
    }

    private static func listFooter(of panel: AgentAccountPanel) -> String? {
        var sentences: [String] = []
        if let footer = panel.footer { sentences.append(footer) }
        if panel.offer.isAvailable {
            sentences.append(
                "Sign in with another \(panel.provider.label) account. Each project can then choose which account runs."
            )
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }
}

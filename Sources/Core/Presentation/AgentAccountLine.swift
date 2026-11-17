import Foundation

public struct AgentAccountLine: Sendable, Equatable {
    public static let unavailableTitle = "Account unavailable"

    public let title: String?
    public let sentence: String
    public let warns: Bool

    public init(title: String?, sentence: String, warns: Bool) {
        self.title = title
        self.sentence = sentence
        self.warns = warns
    }

    public static func make(
        choice: AgentAccountChoice,
        provider: AgentKind,
        standings: [AgentAccountStanding],
        outsideProfile: Bool = false
    ) -> AgentAccountLine {
        let launch = AgentAccountLaunch.decide(choice: choice, provider: provider, outsideUnified: outsideProfile)
        if case .refused(let refusal) = launch {
            return AgentAccountLine(title: unavailableTitle, sentence: refusal.beforeStarting, warns: true)
        }
        let lost = Lost(project: choice.isProjectChoiceLost, profile: choice.isProfileChoiceLost)
        let isLost = lost.any
        let agent = provider.label

        guard let home = choice.home else {
            let sentence = AgentAccountOffer.canEverBeOffered(provider)
                ? "\(agent) has no account chosen here, so it runs with this Mac's own login."
                : "\(agent) has no separate accounts, so it runs with its own login."
            guard isLost else { return AgentAccountLine(title: nil, sentence: sentence, warns: false) }
            return AgentAccountLine(
                title: unavailableTitle,
                sentence: "\(sentence) \(because(lost, agent: agent, leading: "However, ")).",
                warns: true
            )
        }
        let name = AgentAccountNames.title(of: home, among: standings) ?? home.directory.lastPathComponent

        let isGeneric = AgentAccountNames.isGenericDefault(home, among: standings)
        let subject = isGeneric ? "The default account" : name
        let base: String = switch choice.reason {
        case .project:
            "\(subject) runs here, chosen for the project."
        case .profile where isLost:
            "\(subject) runs here, the profile's account, \(because(lost, agent: agent))."
        case .profile:
            "\(subject) runs here, chosen for the profile."
        case .providerDefault where !isLost:
            "\(subject) runs here\(defaultAppositive(isGeneric))."
        case .providerDefault, .noAccount:
            "\(subject) runs here\(defaultAppositive(isGeneric)), \(because(lost, agent: agent))."
        }

        return AgentAccountLine(
            title: name,
            sentence: base + doubt(for: home, in: standings),
            warns: isLost
        )
    }

    private static func defaultAppositive(_ isGeneric: Bool) -> String {
        isGeneric ? "" : ", the default account"
    }

    private static func doubt(for home: AgentAccountHome, in standings: [AgentAccountStanding]) -> String {
        guard !home.isDefault,
              let standing = standings.first(where: { $0.home.id == home.id && $0.home.provider == home.provider }),
              let doubt = standing.isolationDoubt
        else { return "" }
        return " \(doubt)"
    }

    private struct Lost {
        let project: Bool
        let profile: Bool

        var any: Bool { project || profile }
    }

    private static func because(_ lost: Lost, agent: String, leading: String = "because ") -> String {
        switch (lost.project, lost.profile) {
        case (true, true):
            "\(leading)the accounts chosen for the project and for the profile are not available for \(agent)"
        case (false, true):
            "\(leading)the account chosen for the profile is not available for \(agent)"
        default:
            "\(leading)the account chosen for the project is not available for \(agent)"
        }
    }
}

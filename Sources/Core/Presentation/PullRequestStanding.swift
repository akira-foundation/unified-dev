import Foundation

public struct PullRequestStanding: Sendable, Hashable {
    public enum Tone: String, Sendable, Hashable, CaseIterable {
        case quiet
        case accent
        case positive
        case danger
        case warning
        case merged
    }

    public enum Act: String, Sendable, Hashable, CaseIterable {
        case openPullRequest
        case push
        case commitAndPush
        case markReadyForReview
        case merge
        case askToFixChecks
        case askToFixConflicts
        case archive

        public var label: String {
            switch self {
            case .openPullRequest: "Open PR"
            case .push, .commitAndPush: "Push"
            case .markReadyForReview: "Mark ready"
            case .merge: "Merge"
            case .askToFixChecks, .askToFixConflicts: "Ask to fix"
            case .archive: "Archive"
            }
        }
    }

    public struct Button: Sendable, Hashable {
        public var act: Act
        public var sentence: String

        public init(act: Act, sentence: String) {
            self.act = act
            self.sentence = sentence
        }

        public var label: String { act.label }
    }

    public var headline: String
    public var secondary: String
    public var number: Int?
    public var url: String?
    public var state: String?
    public var tone: Tone
    public var button: Button?
    public var current: PullRequestStep?
    public var path: [PullRequestStep]
    public var links: [PullRequestStepLink]
    public var sentence: String

    public init(
        headline: String,
        secondary: String = "",
        number: Int? = nil,
        url: String? = nil,
        state: String? = nil,
        tone: Tone = .quiet,
        button: Button? = nil,
        current: PullRequestStep? = nil,
        path: [PullRequestStep] = [],
        links: [PullRequestStepLink] = [],
        sentence: String = ""
    ) {
        self.headline = headline
        self.secondary = secondary
        self.number = number
        self.url = url
        self.state = state
        self.tone = tone
        self.button = button
        self.current = current
        self.path = path
        self.links = links
        self.sentence = sentence
    }

    public var hostName: String { ForgeRepository.kind(ofRemote: url).displayName }

    public func isReached(_ step: PullRequestStep) -> Bool {
        guard let current, let standing = path.firstIndex(of: current),
              let asked = path.firstIndex(of: step)
        else { return false }
        return asked < standing
    }

    public func reach(of step: PullRequestStep) -> PullRequestReach? {
        links.first { $0.step == step }?.reach
    }

    public func announcement(of step: PullRequestStep) -> String? {
        links.first { $0.step == step }?.announcement
    }

    public static let labelledWidth: CGFloat = 340

    public static func showsLabels(atWidth width: CGFloat) -> Bool {
        width >= labelledWidth
    }

    public static func aheadSentence(_ count: Int, base: String, isCapped: Bool = false) -> String? {
        guard count > 0 else { return nil }
        let number = isCapped ? "more than \(count)" : "\(count)"
        let commits = count == 1 && !isCapped ? "commit" : "commits"
        return "\(number) \(commits) ahead of \(base)"
    }
}

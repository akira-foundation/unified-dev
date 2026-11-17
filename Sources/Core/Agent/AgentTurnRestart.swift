import Foundation

public struct AgentTurnRestart: Sendable, Equatable {
    public enum Step: Sendable, Equatable {
        case chooseAccount
        case switchAgent
    }

    public enum Resolution: Sendable, Equatable {
        case resolved(AgentAccountHome?)
        case failed(String)
    }

    public struct Input: Sendable {
        public var isWorkspaceArchiving: Bool
        public var session: Session
        public var resolution: Resolution
        public var target: AgentAccountHome
        public var isTurnInFlight: Bool
        public var switchRefusal: String?
        public var usesInteractiveTerminal: Bool

        public init(
            isWorkspaceArchiving: Bool,
            session: Session,
            resolution: Resolution,
            target: AgentAccountHome,
            isTurnInFlight: Bool,
            switchRefusal: String?,
            usesInteractiveTerminal: Bool
        ) {
            self.isWorkspaceArchiving = isWorkspaceArchiving
            self.session = session
            self.resolution = resolution
            self.target = target
            self.isTurnInFlight = isTurnInFlight
            self.switchRefusal = switchRefusal
            self.usesInteractiveTerminal = usesInteractiveTerminal
        }
    }

    public struct Refused: Error, Sendable, Equatable {
        public let sentence: String
    }

    public let steps: [Step]
    public let destination: AgentAccountHome

    public static let workspaceArchiving = "The workspace is being archived."
    public static let runsInTerminal =
        "This chat runs its agent in a terminal, so it cannot be moved to another account from here."

    public static func decide(_ input: Input) -> Result<AgentTurnRestart, Refused> {
        let session = input.session
        let provider = session.agentKind
        if input.isWorkspaceArchiving { return refused(workspaceArchiving) }
        if let refusal = input.switchRefusal { return refused(refusal) }
        if input.usesInteractiveTerminal { return refused(runsInTerminal) }
        let from: AgentAccountHome
        switch input.resolution {
        case .failed(let detail):
            return refused("Unified Dev could not work out which account this chat runs under: \(detail)")
        case .resolved(nil):
            return refused(AgentAccountOffer.canEverBeOffered(provider)
                ? "\(provider.label) runs with this Mac's own login here, so this chat cannot be moved to another account."
                : "\(provider.label) has no separate accounts.")
        case .resolved(let home?):
            from = home
        }
        let plan = AgentAccountSwitch.plan(
            session: session, from: from, to: input.target, isTurnInFlight: input.isTurnInFlight
        )
        if plan.refusal != nil {
            return refused("\(input.target.provider.label) accounts cannot run a \(provider.label) chat.")
        }
        guard let destination = plan.destination(of: input.target) else {
            return refused("This chat already runs on that account.")
        }
        return .success(AgentTurnRestart(steps: [.chooseAccount, .switchAgent], destination: destination))
    }

    private static func refused(_ sentence: String) -> Result<AgentTurnRestart, Refused> {
        .failure(Refused(sentence: sentence))
    }
}

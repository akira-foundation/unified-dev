import Foundation

public struct AgentRunnerFingerprint: Sendable, Equatable {
    public let model: String
    public let effort: String
    public let permissionMode: PermissionMode
    public let agentKind: AgentKind
    public let account: AgentAccountID?
    public let accountDirectory: String?
    public let orchestrates: Bool
    public let segment: SessionSegmentID
    public let gitHub: GitHubLogin
    public let usesChrome: Bool

    public init(
        session: Session, account: AgentAccountHome?, orchestrates: Bool, segment: SessionSegmentID,
        gitHub: GitHubLogin = .thisMac, usesChrome: Bool = false
    ) {
        model = session.model
        effort = session.effort
        permissionMode = session.permissionMode
        agentKind = session.agentKind
        self.account = account?.id
        accountDirectory = account?.directory.path
        self.orchestrates = orchestrates
        self.segment = segment
        self.gitHub = gitHub
        self.usesChrome = usesChrome
    }
}

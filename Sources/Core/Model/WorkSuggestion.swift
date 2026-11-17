import Foundation

public struct WorkSuggestion: Identifiable, Sendable, Hashable {
    public enum Target: Sendable, Hashable {
        case sameProject
        case project(RepoID)
        case folder(String)
        case remote(String)
        case orchestrator(RepoID)
    }

    public enum State: Sendable, Hashable {
        case pending
        case starting
        case startedWorkspace(WorkspaceID, name: String)
        case startedHere(SessionID, name: String)
        case dismissed
        case withdrawn

        public var isUndecided: Bool {
            switch self {
            case .pending, .starting: true
            case .startedWorkspace, .startedHere, .dismissed, .withdrawn: false
            }
        }
    }

    public static let undecidedLimit = 5

    public let id: WorkSuggestionID
    public let workspaceID: WorkspaceID?
    public let sessionID: SessionID
    public let anchorSeq: Int?
    public let title: String
    public let why: String
    public let prompt: String
    public let target: Target
    public let state: State
    public let failure: String?
    public let createdAt: Date
    public let decidedAt: Date?

    public init(
        id: WorkSuggestionID = .new(),
        workspaceID: WorkspaceID?,
        sessionID: SessionID,
        title: String,
        why: String,
        prompt: String,
        target: Target,
        createdAt: Date = Date()
    ) {
        self.init(
            stored: id, workspaceID: workspaceID, sessionID: sessionID, anchorSeq: nil,
            title: title, why: why, prompt: prompt, target: target, state: .pending,
            failure: nil, createdAt: createdAt, decidedAt: nil
        )
    }

    init(
        stored id: WorkSuggestionID,
        workspaceID: WorkspaceID?,
        sessionID: SessionID,
        anchorSeq: Int?,
        title: String,
        why: String,
        prompt: String,
        target: Target,
        state: State,
        failure: String?,
        createdAt: Date,
        decidedAt: Date?
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.sessionID = sessionID
        self.anchorSeq = anchorSeq
        self.title = title
        self.why = why
        self.prompt = prompt
        self.target = target
        self.state = state
        self.failure = failure
        self.createdAt = createdAt
        self.decidedAt = decidedAt
    }

    func anchored(at seq: Int) -> WorkSuggestion {
        WorkSuggestion(
            stored: id, workspaceID: workspaceID, sessionID: sessionID, anchorSeq: seq,
            title: title, why: why, prompt: prompt, target: target, state: state,
            failure: failure, createdAt: createdAt, decidedAt: decidedAt
        )
    }
}

import Foundation

public struct SessionSegment: Sendable, Equatable, Identifiable {
    public let id: SessionSegmentID
    public let sessionID: SessionID
    public let agentKind: AgentKind
    public let accountID: AgentAccountID?
    public let agentSessionID: String?
    public let model: String
    public let effort: String
    public let cursorSeq: Int
    public let enteredSeq: Int
    public let isActive: Bool
    public let sourceReceivedSeq: Int?

    public init(
        id: SessionSegmentID,
        sessionID: SessionID,
        agentKind: AgentKind,
        accountID: AgentAccountID?,
        agentSessionID: String?,
        model: String,
        effort: String,
        cursorSeq: Int,
        enteredSeq: Int,
        isActive: Bool,
        sourceReceivedSeq: Int?
    ) {
        self.id = id
        self.sessionID = sessionID
        self.agentKind = agentKind
        self.accountID = accountID
        self.agentSessionID = agentSessionID
        self.model = model
        self.effort = effort
        self.cursorSeq = cursorSeq
        self.enteredSeq = enteredSeq
        self.isActive = isActive
        self.sourceReceivedSeq = sourceReceivedSeq
    }
}

public struct SessionSegmentTarget: Sendable, Equatable {
    public let agentKind: AgentKind
    public let accountID: AgentAccountID?
    public let model: String
    public let effort: String
    public let accountName: String?

    public init(
        agentKind: AgentKind, accountID: AgentAccountID?, model: String, effort: String, accountName: String? = nil
    ) {
        self.agentKind = agentKind
        self.accountID = accountID
        self.model = model
        self.effort = effort
        self.accountName = accountName
    }

    public func named(_ name: String?) -> SessionSegmentTarget {
        SessionSegmentTarget(agentKind: agentKind, accountID: accountID, model: model, effort: effort, accountName: name)
    }
}

public struct RunnerSeat: Sendable, Equatable {
    public let session: Session
    public let segmentID: SessionSegmentID
    public var lostItsAccount = false
}

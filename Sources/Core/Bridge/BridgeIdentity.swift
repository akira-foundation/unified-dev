import Foundation

public enum BridgeRole: String, Sendable, Hashable, Codable, CaseIterable {
    case workspace
    case owner
}

public struct BridgeIdentity: Sendable, Hashable {
    public let sessionID: SessionID?
    public let workspaceID: WorkspaceID?
    public let role: BridgeRole
    public let pinnedProfile: ProfileID?
    public let launchedOrchestrating: Bool
    public let launchedAsking: Bool

    public init(
        sessionID: SessionID,
        workspaceID: WorkspaceID,
        role: BridgeRole,
        launchedOrchestrating: Bool = false,
        launchedAsking: Bool = false
    ) {
        self.sessionID = sessionID
        self.workspaceID = workspaceID
        self.role = role
        self.pinnedProfile = nil
        self.launchedOrchestrating = launchedOrchestrating
        self.launchedAsking = launchedAsking
    }

    private init(role: BridgeRole) {
        self.sessionID = nil
        self.workspaceID = nil
        self.role = role
        self.pinnedProfile = nil
        self.launchedOrchestrating = false
        self.launchedAsking = false
    }

    public init(ownerSession sessionID: SessionID, pinnedProfile: ProfileID? = nil) {
        self.sessionID = sessionID
        self.workspaceID = nil
        self.role = .owner
        self.pinnedProfile = pinnedProfile
        self.launchedOrchestrating = false
        self.launchedAsking = false
    }

    public static let owner = BridgeIdentity(role: .owner)
}

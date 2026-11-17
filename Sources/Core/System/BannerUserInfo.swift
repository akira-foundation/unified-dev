import Foundation

public enum BannerUserInfo {
    private static let workspaceKey = "unifieddevWorkspaceID"
    private static let sessionKey = "unifieddevSessionID"

    public static func encode(workspaceID: WorkspaceID, sessionID: SessionID? = nil) -> [String: String] {
        var info = [workspaceKey: workspaceID.rawValue]
        if let sessionID { info[sessionKey] = sessionID.rawValue }
        return info
    }

    public static func workspaceID(from userInfo: [AnyHashable: Any]) -> WorkspaceID? {
        guard let raw = userInfo[workspaceKey] as? String, !raw.isEmpty else { return nil }
        return WorkspaceID(raw)
    }

    public static func sessionID(from userInfo: [AnyHashable: Any]) -> SessionID? {
        guard let raw = userInfo[sessionKey] as? String, !raw.isEmpty else { return nil }
        return SessionID(raw)
    }
}

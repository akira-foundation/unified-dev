import Foundation

public enum TranscriptRetention {
    public static let keptIdleChats = 4
    public static let keptWorkspaces = 3

    public struct Chat: Equatable, Sendable {
        public var session: SessionID
        public var workspace: WorkspaceID?
        public var holdsRows: Bool
        public var isShown: Bool
        public var isBusy: Bool
        public var lastShown: Int

        public init(
            session: SessionID,
            workspace: WorkspaceID?,
            holdsRows: Bool,
            isShown: Bool,
            isBusy: Bool,
            lastShown: Int
        ) {
            self.session = session
            self.workspace = workspace
            self.holdsRows = holdsRows
            self.isShown = isShown
            self.isBusy = isBusy
            self.lastShown = lastShown
        }

        var isHeld: Bool { isShown || isBusy }
    }

    public static func chatsToRelease(_ chats: [Chat], selected: WorkspaceID?) -> [SessionID] {
        let idle = chats.filter { $0.holdsRows && !$0.isHeld && ($0.workspace == nil || $0.workspace != selected) }
        let kept = Set(idle.sorted { $0.lastShown > $1.lastShown }.prefix(keptIdleChats).map(\.session))
        return idle.filter { !kept.contains($0.session) }.map(\.session)
    }

    public static func workspacesToRelease(
        _ workspaces: [WorkspaceID], chats: [Chat], selected: WorkspaceID?
    ) -> [WorkspaceID] {
        var lastShown: [WorkspaceID: Int] = [:]
        var held: Set<WorkspaceID> = []
        for chat in chats {
            guard let workspace = chat.workspace else { continue }
            lastShown[workspace] = max(lastShown[workspace] ?? 0, chat.lastShown)
            if chat.isHeld { held.insert(workspace) }
        }
        let candidates = workspaces.filter { $0 != selected && !held.contains($0) }
        let kept = Set(candidates.sorted { (lastShown[$0] ?? 0) > (lastShown[$1] ?? 0) }.prefix(keptWorkspaces))
        return candidates.filter { !kept.contains($0) }
    }
}

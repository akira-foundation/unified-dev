import Foundation

public struct DiffLoadIdentity: Hashable, Sendable {
    public var workspaceID: WorkspaceID
    public var file: ChangedFile
    public var revision: String?
    public var scope: DiffScope
    public var language: Language
    public var isCollapsed: Bool
    public var ignoringWhitespace: Bool

    public init(
        workspaceID: WorkspaceID,
        file: ChangedFile,
        revisions: [String: String],
        scope: DiffScope,
        language: Language,
        isCollapsed: Bool,
        ignoringWhitespace: Bool
    ) {
        self.workspaceID = workspaceID
        self.file = file
        self.revision = revisions[file.path]
        self.scope = scope
        self.language = language
        self.isCollapsed = isCollapsed
        self.ignoringWhitespace = ignoringWhitespace
    }
}

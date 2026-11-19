import Foundation

public struct FileTabDraftControls: Sendable, Equatable {
    public var watchesDisk: Bool
    public var canSave: Bool
    public var showsDiskChange: Bool
    public var canOverwriteDisk: Bool

    public init(
        mode: FileTabMode, canEdit: Bool, hasDraft: Bool, isDirty: Bool, isSaving: Bool, changedOnDisk: Bool
    ) {
        watchesDisk = mode != .preview || hasDraft
        canSave = canEdit && hasDraft && isDirty && !isSaving
        showsDiskChange = hasDraft && changedOnDisk
        canOverwriteDisk = canEdit && showsDiskChange && !isSaving
    }
}

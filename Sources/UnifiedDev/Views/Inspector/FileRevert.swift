import Foundation
import Core

enum FileRevert {
    @MainActor
    static func hasUnsavedEdits(at absolutePath: String) -> Bool {
        FileEditSession.shared.isDirty(absolutePath) || DiffEditSession.shared.isEdited(absolutePath)
    }

    @MainActor
    static func unsavedPaths() -> [String] {
        Set(FileEditSession.shared.unsavedPaths).union(DiffEditSession.shared.editedPaths).sorted()
    }
}

import Foundation
import Core

extension FileEditSession {
    func controls(for absolutePath: String, mode: FileTabMode, canEdit: Bool) -> FileTabDraftControls {
        FileTabDraftControls(
            mode: mode, canEdit: canEdit, hasDraft: draft(for: absolutePath) != nil,
            isDirty: isDirty(absolutePath), isSaving: saving.contains(absolutePath),
            changedOnDisk: diskVersions[absolutePath] != nil
        )
    }

    func watch(path absolutePath: String) async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            await refresh(path: absolutePath)
        }
    }

    func save(path absolutePath: String, reviewing path: String, in model: WorkspaceModel) async -> Bool {
        await save(path: absolutePath)
        return await settle(absolutePath, reviewing: path, in: model)
    }

    func keepDraftOverDisk(path absolutePath: String, reviewing path: String, in model: WorkspaceModel) async -> Bool {
        await keepDraftOverDisk(path: absolutePath)
        return await settle(absolutePath, reviewing: path, in: model)
    }

    private func settle(_ absolutePath: String, reviewing path: String, in model: WorkspaceModel) async -> Bool {
        guard case .saved = status(for: absolutePath) else { return false }
        model.forgetHeldDiff(for: path)
        await model.refreshChanges()
        return true
    }
}

import Foundation
import Core

extension WorkspaceModel {
    func revert(_ file: ChangedFile) async -> RevertAlert? {
        let absolute = (workspace.path as NSString).appendingPathComponent(file.path)
        let outcome = await WorktreeFileRevert.revert(file, in: workspace, refusal: revertBlocker)
        if outcome.discardsDraft {
            FileEditSession.shared.discard(path: absolute)
            DiffEditSession.shared.close(path: absolute)
        }
        if outcome.refreshesChanges {
            forgetHeldDiff(for: file.path)
            await refreshChanges()
        }
        return RevertAlert(outcome, filename: file.filename)
    }

    func hunkDiscard(
        for file: ChangedFile, in diff: FileDiff?, ignoringWhitespace: Bool, staged: HunkDiscard.Staged = .clean
    ) -> HunkDiscard.Availability {
        HunkDiscard.availability(
            file: file, in: diff, ignoringWhitespace: ignoringWhitespace, blocker: revertBlocker,
            hasUnsavedEdits: hasUnsavedEdits(file), staged: staged
        )
    }

    func hunkRefusals(for file: ChangedFile, in diff: FileDiff) async -> [DiffHunk: HunkDiscard.Staged] {
        guard hunkRefusal(for: file, in: diff) == nil else { return [:] }
        return await Git.hunkRefusals(
            in: diff, of: file, worktree: workspace.path, base: workspace.baseBranch, scope: diffScope
        )
    }

    func stagedHunk(_ hunk: DiffHunk, of file: ChangedFile, in diff: FileDiff?) async -> HunkDiscard.Staged {
        guard hunkRefusal(for: file, in: diff) == nil else { return .clean }
        return await Git.stagedHunk(
            hunk, of: file, worktree: workspace.path, base: workspace.baseBranch, scope: diffScope
        )
    }

    func discard(_ hunk: DiffHunk, of file: ChangedFile, in diff: FileDiff?) async -> RevertAlert? {
        let outcome = await WorktreeHunkDiscard.discard(
            hunk, of: file, in: workspace, scope: diffScope,
            refusal: hunkRefusal(for: file, in: diff)
        )
        if outcome.refreshesChanges {
            forgetHeldDiff(for: file.path)
            await refreshChanges()
        }
        return RevertAlert(outcome, filename: file.filename)
    }

    private func hunkRefusal(for file: ChangedFile, in diff: FileDiff?) -> String? {
        HunkDiscard.refusal(
            file: file, in: diff,
            ignoringWhitespace: UserDefaults.standard.bool(forKey: DiffWhitespaceSetting.storageKey),
            blocker: revertBlocker, hasUnsavedEdits: hasUnsavedEdits(file)
        )
    }

    private func hasUnsavedEdits(_ file: ChangedFile) -> Bool {
        FileRevert.hasUnsavedEdits(at: (workspace.path as NSString).appendingPathComponent(file.path))
    }
}

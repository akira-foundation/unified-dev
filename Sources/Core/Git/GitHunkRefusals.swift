import Foundation

extension Git {
    public static func hunkRefusals(
        in shown: FileDiff, of file: ChangedFile, worktree: String, base: String, scope: DiffScope
    ) async -> [DiffHunk: HunkDiscard.Staged] {
        guard HunkDiscard.offers(file, in: shown) else { return [:] }
        let staged = await indexStandsApart(file, in: worktree)
        let suspects = shown.hunks.filter { staged || HunkDiscard.mayAddLinesThatAreNotUTF8($0) }
        guard !suspects.isEmpty, !Task.isCancelled,
              let patches = try? await hunkDiscardPatches(of: file, worktree: worktree, base: base, scope: scope)
        else { return [:] }

        var refused: [DiffHunk: HunkDiscard.Staged] = [:]
        for hunk in suspects {
            guard !Task.isCancelled else { return [:] }
            refused[hunk] = await refusal(of: hunk, in: patches, staged: staged, worktree: worktree)
        }
        return refused
    }

    static func indexStandsApart(_ file: ChangedFile, in worktree: String) async -> Bool {
        guard (try? await stagedContentDiffers(file, in: worktree)) == true else { return false }
        let worktreeCheck = try? await run(
            literalPaths(["diff", "--quiet", "--"] + pathspecs(of: file)), in: worktree
        )
        return worktreeCheck?.status != 0
    }

    private static func refusal(
        of hunk: DiffHunk, in patches: HunkDiscardPatches, staged: Bool, worktree: String
    ) async -> HunkDiscard.Staged? {
        let plan: HunkDiscardPlan
        do {
            plan = try hunkDiscardPlan(hunk, in: patches)
        } catch HunkDiscardRefusal.addsLinesThatAreNotUTF8 {
            return .addsLinesThatAreNotUTF8
        } catch {
            return nil
        }
        guard staged, let route = try? await route(plan, in: worktree) else { return nil }
        return HunkDiscard.canConfirm(route.staged) ? nil : route.staged
    }
}

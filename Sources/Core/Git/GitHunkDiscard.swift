import Foundation

enum HunkDiscardRoute: Equatable, Sendable {
    case indexAndWorktree
    case refusedByTheIndex
    case worktreeOnly
}

struct HunkDiscardPlan: Sendable {
    let isolated: Data
    let anchored: Data
    let hasPreimage: Bool
}

extension Git {
    public static func discardHunk(
        _ hunk: DiffHunk, of file: ChangedFile, worktree: String, base: String, scope: DiffScope
    ) async throws {
        let plan = try await hunkDiscardPlan(
            hunk, of: file, worktree: worktree, base: base, scope: scope
        )
        try await apply(plan, in: worktree)
    }

    static func hunkDiscardPlan(
        _ hunk: DiffHunk, of file: ChangedFile, worktree: String, base: String, scope: DiffScope
    ) async throws -> HunkDiscardPlan {
        guard HunkDiscard.offers(file) else { throw HunkDiscardRefusal.notOffered }

        let current = try await trackedPatch(worktree: worktree, base: base, file: file, scope: scope)
        let parsed = DiffParser.parse(String(decoding: current, as: UTF8.self))
        guard parsed.count == 1, let shown = parsed.first,
              HunkDiscard.offers(file, in: shown) else { throw HunkDiscardRefusal.notOffered }

        let whole = try await trackedPatch(
            worktree: worktree, base: base, file: file, scope: scope,
            context: HunkPatch.wholeFileContext
        )
        guard let isolated = HunkPatch.isolate(hunk, from: current),
              let anchored = HunkPatch.anchor(hunk, in: whole)
        else { throw HunkDiscardRefusal.changed }
        guard !HunkPatch.addsLinesThatAreNotUTF8(anchored) else {
            throw HunkDiscardRefusal.addsLinesThatAreNotUTF8
        }

        return HunkDiscardPlan(isolated: isolated, anchored: anchored, hasPreimage: hunk.newCount > 0)
    }

    static func apply(_ plan: HunkDiscardPlan, in worktree: String) async throws {
        let reverse = ["apply", "--reverse", "--whitespace=nowarn"]
        switch try await route(plan, in: worktree) {
        case .indexAndWorktree:
            try await checkRaw(reverse + ["--index"], in: worktree, input: plan.anchored)
        case .refusedByTheIndex:
            throw HunkDiscardRefusal.indexDiffers
        case .worktreeOnly:
            let worktreeCheck = try await runRaw(reverse + ["--check"], in: worktree, input: plan.anchored)
            guard worktreeCheck.ok else {
                throw HunkDiscardRefusal.doesNotApply(
                    worktreeCheck.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            try await checkRaw(reverse, in: worktree, input: plan.anchored)
        }
    }

    static func route(_ plan: HunkDiscardPlan, in worktree: String) async throws -> HunkDiscardRoute {
        let reverse = ["apply", "--reverse", "--whitespace=nowarn"]
        if try await runRaw(reverse + ["--index", "--check"], in: worktree, input: plan.anchored).ok {
            return .indexAndWorktree
        }
        if plan.hasPreimage,
           try await runRaw(reverse + ["--cached", "--check"], in: worktree, input: plan.isolated).ok {
            return .refusedByTheIndex
        }
        return .worktreeOnly
    }
}

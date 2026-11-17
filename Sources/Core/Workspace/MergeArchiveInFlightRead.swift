import Foundation

public enum MergeArchiveInFlightRead {
    private static let gitTimeout = Duration.seconds(20)
    private static let branchPrefix = "refs/heads/"
    private static let detachedStatus: Int32 = 1

    public static func objection(worktree: String, mergedHead: String?) async -> String? {
        do {
            let names = try await candidates(in: worktree)
            guard names.count <= MergeArchiveInFlight.branchLimit else {
                return MergeArchiveInFlight.tooManyBranches
            }
            await Git.pruneStaleRemoteRefs(in: worktree)
            let remoteTips = try await lines(
                ["for-each-ref", "--format=%(objectname)", "refs/remotes"], in: worktree
            )
            var standings: [BranchInFlight] = []
            for name in names {
                let pullRequests = try await GitHub.pullRequestsWithHead(name, worktree: worktree)
                let heads = await present(
                    MergeArchiveInFlight.publishedHeads(pullRequests, mergedHead: mergedHead), in: worktree
                )
                let unpushed = try await Git.commitCount(
                    of: branchPrefix + name, excluding: remoteTips + heads, in: worktree
                )
                standings.append(
                    MergeArchiveInFlight.standing(branch: name, pullRequests: pullRequests, unpushedCommits: unpushed)
                )
            }
            return MergeArchiveInFlight.objection(standings)
        } catch {
            return MergeArchiveInFlight.unreadable
        }
    }

    static func candidates(in worktree: String) async throws -> [String] {
        let reflog = try await lines(["reflog", "show", "--format=%gs", "HEAD"], in: worktree)
        let head = try await Git.run(["symbolic-ref", "--quiet", "HEAD"], in: worktree, timeout: gitTimeout)
        guard head.ok || head.status == detachedStatus else {
            throw Git.error(["symbolic-ref"], head.status, head.stderr, head.stdout)
        }
        let local = try await lines(["for-each-ref", "--format=%(refname)", "refs/heads"], in: worktree)
        return MergeArchiveInFlight.candidates(
            checkedOut: MergeArchiveInFlight.checkedOutBranches(reflogSubjects: reflog.joined(separator: "\n")),
            current: head.ok ? branchName(head.trimmed) : nil,
            localBranches: Set(local.compactMap(branchName))
        )
    }

    private static func branchName(_ ref: String) -> String? {
        ref.hasPrefix(branchPrefix) ? String(ref.dropFirst(branchPrefix.count)) : nil
    }

    private static func present(_ commits: [String], in worktree: String) async -> [String] {
        var known: [String] = []
        for commit in commits where Git.isCommitID(commit) {
            if await Git.revision(of: commit, in: worktree) != nil { known.append(commit) }
        }
        return known
    }

    private static func lines(_ arguments: [String], in worktree: String) async throws -> [String] {
        let result = try await Git.run(arguments, in: worktree, timeout: gitTimeout)
        guard result.ok else { throw Git.error(arguments, result.status, result.stderr, result.stdout) }
        return result.stdout.split(whereSeparator: \.isNewline).map(String.init)
    }
}

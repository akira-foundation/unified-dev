import Foundation

public struct BranchInFlight: Sendable, Equatable {
    public let branch: String
    public let openPullRequests: [Int]
    public let unpushedCommits: Int

    public init(branch: String, openPullRequests: [Int], unpushedCommits: Int) {
        self.branch = branch
        self.openPullRequests = openPullRequests
        self.unpushedCommits = unpushedCommits
    }
}

public enum MergeArchiveInFlight {
    public static let branchLimit = 30

    public static let unreadable = "Unified Dev could not check this workspace's other branches for work "
        + "still in flight. Nothing was archived; try again shortly."

    public static let tooManyBranches = "This workspace has checked out more than \(branchLimit) branches, "
        + "too many to check for work still in flight. Nothing was archived; archive it by hand once you "
        + "have checked them."

    public static let nextStep = "Archive it by hand once that work is done."

    public static func objection(_ branches: [BranchInFlight]) -> String? {
        let open = Array(Set(branches.flatMap(\.openPullRequests))).sorted()
        let unpushed = branches.filter { $0.unpushedCommits > 0 }
        var sentences: [String] = []
        if !open.isEmpty {
            sentences.append("\(list(open.map { "#\($0)" })) \(open.count == 1 ? "is" : "are") still open.")
        }
        for branch in unpushed {
            let one = branch.unpushedCommits == 1
            let commits = one ? "1 commit" : "\(branch.unpushedCommits) commits"
            sentences.append("\(branch.branch) has \(commits) that \(one ? "is" : "are") not pushed.")
        }
        guard !sentences.isEmpty else { return nil }
        return (sentences + [nextStep]).joined(separator: " ")
    }

    public static func checkedOutBranches(reflogSubjects: String) -> [String] {
        let prefix = "checkout: moving from "
        var seen: [String] = []
        for line in reflogSubjects.split(whereSeparator: \.isNewline) where line.hasPrefix(prefix) {
            let parts = line.dropFirst(prefix.count).components(separatedBy: " to ")
            guard parts.count == 2 else { continue }
            for name in [parts[1], parts[0]] where !name.isEmpty && !seen.contains(name) {
                seen.append(name)
            }
        }
        return seen
    }

    public static func candidates(checkedOut: [String], current: String?, localBranches: Set<String>) -> [String] {
        var ordered: [String] = []
        for name in [current].compactMap(\.self) + checkedOut
        where localBranches.contains(name) && !ordered.contains(name) {
            ordered.append(name)
        }
        return ordered
    }

    public static func publishedHeads(_ pullRequests: [PullRequestHeadMatch], mergedHead: String?) -> [String] {
        (pullRequests.compactMap(\.headCommit) + [mergedHead].compactMap(\.self)).filter { !$0.isEmpty }
    }

    public static func standing(
        branch: String, pullRequests: [PullRequestHeadMatch], unpushedCommits: Int
    ) -> BranchInFlight {
        BranchInFlight(
            branch: branch,
            openPullRequests: pullRequests.filter(\.isOpen).map(\.number).sorted(),
            unpushedCommits: unpushedCommits
        )
    }

    private static func list(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}

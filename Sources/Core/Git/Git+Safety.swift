import Foundation

public enum ReproduciblePaths {
    public static let directories: Set<String> = [
        ".unifieddev", ".superpowers",
        "node_modules", "bower_components", "jspm_packages", ".pnpm", ".pnpm-store", ".yarn",
        "vendor", "Pods", "Carthage", ".venv", "venv", "virtualenv", ".tox", ".bundle",
        ".cargo", ".gradle", ".m2", ".stack-work", ".pub-cache", ".dart_tool", "_build",
        "dist", "build", ".build", "target", ".next", ".nuxt", ".output", ".svelte-kit",
        ".astro", ".docusaurus", ".vercel", ".netlify", "DerivedData", ".swiftpm",
        ".cache", ".turbo", ".parcel-cache", ".vite", "__pycache__", ".pytest_cache",
        ".mypy_cache", ".ruff_cache", ".phpunit.cache", ".sass-cache", ".nyc_output",
        ".terraform", ".serverless", "coverage",
    ]

    public static let files: Set<String> = [
        ".DS_Store", "Thumbs.db", ".eslintcache", ".phpunit.result.cache",
    ]

    public static let suffixes = [".pyc", ".pyo", ".class"]

    public static func canBeRebuilt(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let last = components.last.map(String.init) else { return false }

        if components.contains(where: { directories.contains(String($0)) }) { return true }
        if files.contains(last) { return true }
        return suffixes.contains { last.hasSuffix($0) }
    }
}

public struct WorkspaceSafetyReport: Sendable, Hashable {
    public var hasUncommittedChanges: Bool
    public var untrackedFiles: [String]
    public var unpushedCommits: Int
    public var commitsAfterPullRequest: Int?
    public var isBranchMerged: Bool
    public var modifiedIgnoredFiles: [String]
    public var detachedCommits: Int
    public var branchTip: String?

    public var preservedFolderPath: String?

    public init(
        hasUncommittedChanges: Bool = false,
        untrackedFiles: [String] = [],
        unpushedCommits: Int = 0,
        commitsAfterPullRequest: Int? = nil,
        isBranchMerged: Bool = false,
        modifiedIgnoredFiles: [String] = [],
        detachedCommits: Int = 0
    ) {
        self.hasUncommittedChanges = hasUncommittedChanges
        self.untrackedFiles = untrackedFiles
        self.unpushedCommits = unpushedCommits
        self.commitsAfterPullRequest = commitsAfterPullRequest
        self.isBranchMerged = isBranchMerged
        self.modifiedIgnoredFiles = modifiedIgnoredFiles
        self.detachedCommits = detachedCommits
    }

    public var isSafeToDiscard: Bool {
        isSafeToDiscard(deletingBranch: true)
    }

    public func isSafeToDiscard(deletingBranch: Bool, isPullRequestMerged: Bool = false) -> Bool {
        let workingCopyIsClean = !hasUncommittedChanges
            && untrackedFiles.isEmpty
            && modifiedIgnoredFiles.isEmpty
            && detachedCommits == 0

        guard workingCopyIsClean else { return false }
        return commitsLostWithBranch(deletingBranch: deletingBranch, isPullRequestMerged: isPullRequestMerged) == 0
    }

    public func commitsLostWithBranch(deletingBranch: Bool, isPullRequestMerged: Bool = false) -> Int {
        guard deletingBranch, !isBranchMerged else { return 0 }
        guard isPullRequestMerged, let commitsAfterPullRequest else { return unpushedCommits }
        return min(commitsAfterPullRequest, unpushedCommits)
    }

    public var losses: [String] {
        losses(deletingBranch: true)
    }

    public func losses(deletingBranch: Bool, isPullRequestMerged: Bool = false) -> [String] {
        irreversibleLosses(deletingBranch: deletingBranch, isPullRequestMerged: isPullRequestMerged)
            + ignoredFileNotes
    }

    public func irreversibleLosses(
        deletingBranch: Bool, isPullRequestMerged: Bool = false
    ) -> [String] {
        var losses: [String] = []
        if hasUncommittedChanges {
            losses.append("uncommitted changes to tracked files")
        }
        if !untrackedFiles.isEmpty {
            let sample = untrackedFiles.prefix(5).joined(separator: ", ")
            let rest = untrackedFiles.count > 5 ? ", and \(untrackedFiles.count - 5) more" : ""
            losses.append("\(Self.count(untrackedFiles.count, "untracked file")): \(sample)\(rest)")
        }
        let lostCommits = commitsLostWithBranch(
            deletingBranch: deletingBranch, isPullRequestMerged: isPullRequestMerged
        )
        if lostCommits > 0 {
            losses.append(
                "\(Self.count(lostCommits, "commit")) that "
                + "\(lostCommits == 1 ? "exists" : "exist") on no other branch, tag or remote"
            )
        }
        if detachedCommits > 0 {
            losses.append(
                "\(Self.count(detachedCommits, "commit")) made on a detached HEAD, "
                + "held by no branch"
            )
        }
        return losses
    }

    public var ignoredFileNotes: [String] {
        guard !modifiedIgnoredFiles.isEmpty else { return [] }

        let sample = modifiedIgnoredFiles.prefix(5).joined(separator: ", ")
        let rest = modifiedIgnoredFiles.count > 5
            ? ", and \(modifiedIgnoredFiles.count - 5) more"
            : ""
        let folders = modifiedIgnoredFiles.contains { $0.hasSuffix("/") }
        let one = modifiedIgnoredFiles.count == 1
        let noun = switch (one, folders) {
        case (true, true): "ignored folder"
        case (true, false): "ignored file"
        case (false, true): "ignored files and folders"
        case (false, false): "ignored files"
        }
        return [
            "\(modifiedIgnoredFiles.count) \(noun) that \(one ? "differs" : "differ") "
            + "from the main checkout: \(sample)\(rest)"
        ]
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}

extension Git {
    public static func safetyReport(
        worktree: String,
        branch: String,
        base: String,
        repo: String,
        mergedPullRequestHead: String? = nil
    ) async throws -> WorkspaceSafetyReport {
        try validate(branch: branch)

        var report = WorkspaceSafetyReport()

        var isDetached = false
        if FileManager.default.fileExists(atPath: worktree) {
            guard await isRepository(worktree) else {
                throw ShellError(
                    command: "git status",
                    status: 128,
                    stderr: "\(worktree) is not a git worktree, so what is in it cannot be checked"
                )
            }
            let status = try await checkRaw(["status", "--porcelain", "-z"], in: worktree)
            (report.hasUncommittedChanges, report.untrackedFiles) = parseStatus(status.stdout)
            report.modifiedIgnoredFiles = try await divergentIgnoredFiles(worktree: worktree, repo: repo)
            isDetached = try await isDetachedHead(worktree: worktree)
        }

        let branchIsThere = await branchExists(branch, in: repo)
        guard isDetached || branchIsThere else { return report }

        await pruneStaleRemoteRefs(in: repo)
        let refs = try await allRefs(in: repo)

        if isDetached {
            report.detachedCommits = (try? await commitCount(of: "HEAD", excluding: refs, in: worktree)) ?? 0
        }
        guard branchIsThere else { return report }

        report.branchTip = await revision(of: "refs/heads/\(branch)", in: repo)
        let others = refs.filter { $0 != "refs/heads/\(branch)" }
        report.unpushedCommits = try await commitCount(of: "refs/heads/\(branch)", excluding: others, in: repo)

        if let mergedPullRequestHead, let head = await pullRequestHead(mergedPullRequestHead, in: repo) {
            report.commitsAfterPullRequest = try await commitCount(
                of: "refs/heads/\(branch)", excluding: others + [head], in: repo
            )
        }

        if base != branch, (try? validate(ref: base, label: "base branch")) != nil {
            let merged = try await run(
                ["merge-base", "--is-ancestor", "refs/heads/\(branch)", base], in: repo
            )
            report.isBranchMerged = merged.ok
        }

        return report
    }

    static func parseStatus(_ data: Data) -> (dirty: Bool, untracked: [String]) {
        var dirty = false
        var untracked: [String] = []
        var records = nulRecords(data)[...]

        while let record = records.popFirst() {
            guard record.count > 3 else { continue }
            let code = String(decoding: record.prefix(2), as: UTF8.self)
            let path = String(decoding: record.dropFirst(3), as: UTF8.self)
            if code == "??" {
                untracked.append(path)
            } else {
                dirty = true
                if code.contains("R") || code.contains("C") { _ = records.popFirst() }
            }
        }
        return (dirty, untracked)
    }

    static func divergentIgnoredFiles(worktree: String, repo: String) async throws -> [String] {
        let covering = try await ignoredWork(worktree: worktree)
        let plans = try await AgentPlans.keepable(among: covering, worktree: worktree, repo: repo)

        var divergent: [String] = []
        for path in covering {
            let here = (worktree as NSString).appendingPathComponent(path)
            let there = (repo as NSString).appendingPathComponent(path)
            let isFolder = path.hasSuffix("/")
            let differs = plans.contains(path)
                ? AgentPlans.collides(here, there)
                : (isFolder ? directoryDiffers(here, there) : fileDiffers(here, there))
            if differs { divergent.append(path) }
        }
        return divergent.sorted()
    }

    static func ignoredWork(worktree: String) async throws -> [String] {
        var listed: Set<String> = []
        for path in try await listIgnored(["--directory"], in: worktree) {
            if AgentPlans.mayHoldPlans(path, worktree: worktree) {
                listed.formUnion(try await listIgnored(["--", path], in: worktree))
            } else {
                listed.insert(path)
            }
        }

        let paths = listed.filter { $0.hasPrefix(AgentPlans.folder) || !ReproduciblePaths.canBeRebuilt($0) }
        let directories = paths.filter { $0.hasSuffix("/") }
        return paths.filter { path in
            !directories.contains { $0 != path && path.hasPrefix($0) }
        }
    }

    private static func listIgnored(_ arguments: [String], in worktree: String) async throws -> [String] {
        let ignored = try await checkRaw(
            ["--literal-pathspecs", "ls-files", "--others", "--ignored", "--exclude-standard", "-z"] + arguments,
            in: worktree
        )
        return nulRecords(ignored.stdout)
            .map { String(decoding: $0, as: UTF8.self) }
            .filter { !$0.isEmpty }
    }

    static func fileDiffers(_ here: String, _ there: String) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: here) else { return false }
        guard manager.fileExists(atPath: there) else { return true }

        let mySize = (try? manager.attributesOfItem(atPath: here)[.size] as? Int)
        let theirSize = (try? manager.attributesOfItem(atPath: there)[.size] as? Int)
        if let mySize, let theirSize, mySize != theirSize { return true }

        guard let mine = manager.contents(atPath: here) else { return true }
        guard let theirs = manager.contents(atPath: there) else { return true }
        return mine != theirs
    }

    static func directoryDiffers(_ here: String, _ there: String, limit: Int = 2_000) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: here) else { return false }
        guard manager.fileExists(atPath: there) else { return true }

        guard let walk = manager.enumerator(atPath: here) else { return true }
        var seen = 0
        for case let relative as String in walk {
            var isDirectory: ObjCBool = false
            let file = (here as NSString).appendingPathComponent(relative)
            guard manager.fileExists(atPath: file, isDirectory: &isDirectory), !isDirectory.boolValue
            else { continue }

            seen += 1
            if seen > limit { return true }
            if fileDiffers(file, (there as NSString).appendingPathComponent(relative)) { return true }
        }
        return false
    }

    static func isDetachedHead(worktree: String) async throws -> Bool {
        let head = try await run(["symbolic-ref", "--quiet", "HEAD"], in: worktree)
        return !head.ok
    }

    static func commitCount(of tip: String, excluding refs: [String], in directory: String) async throws -> Int {
        let negated = refs.map { "^\($0)" }.joined(separator: "\n")
        let unique = try await check(
            ["rev-list", "--count", "--stdin", tip],
            in: directory,
            stdin: negated.isEmpty ? "\n" : negated + "\n"
        )
        return Int(unique.trimmed) ?? 0
    }

    static func isCommitID(_ value: String) -> Bool {
        [40, 64].contains(value.count) && value.allSatisfy(\.isHexDigit)
    }

    static func pullRequestHead(
        _ commit: String, in repo: String, timeout: Duration = .seconds(10)
    ) async -> String? {
        guard isCommitID(commit) else { return nil }
        if let local = await revision(of: commit, in: repo) { return local }
        for remote in (try? await remoteNames(of: repo)) ?? []
        where (try? validate(ref: remote, label: "remote")) != nil {
            _ = try? await runAgainstRemote(
                ["fetch", "--no-tags", "--no-write-fetch-head", remote, commit], in: repo, timeout: timeout
            )
            if let fetched = await revision(of: commit, in: repo) { return fetched }
        }
        return nil
    }

    static func pruneStaleRemoteRefs(in repo: String, timeout: Duration = .seconds(10)) async {
        for remote in (try? await remoteNames(of: repo)) ?? []
        where (try? validate(ref: remote, label: "remote")) != nil {
            guard await fetchesOnlyIntoRemoteRefs(remote, in: repo) else { continue }
            _ = try? await runAgainstRemote(["remote", "prune", remote], in: repo, timeout: timeout)
        }
    }

    static func fetchesOnlyIntoRemoteRefs(_ remote: String, in repo: String) async -> Bool {
        guard let result = try? await run(["config", "--get-all", "remote.\(remote).fetch"], in: repo),
              result.ok
        else { return false }
        let refspecs = result.lines.filter { !$0.hasPrefix("^") }
        return !refspecs.isEmpty && refspecs.allSatisfy { refspec in
            guard let destination = refspec.split(separator: ":", maxSplits: 1).last,
                  refspec.contains(":")
            else { return false }
            return destination.hasPrefix("refs/remotes/")
        }
    }

    static func allRefs(in repo: String) async throws -> [String] {
        try await check(
            ["for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes", "refs/tags"],
            in: repo
        ).lines
    }
}

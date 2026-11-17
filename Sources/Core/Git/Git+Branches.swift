import Foundation

extension Git {
    public static func renameBranch(_ old: String, to new: String, in directory: String) async throws {
        try validate(branch: old)
        try validate(branch: new)
        try await check(["branch", "-m", "--", old, new], in: directory)
    }

    public static let remote = "origin"

    public static func fetch(
        _ branch: String, in directory: String, remote: String? = nil,
        timeout: Duration = .seconds(20)
    ) async -> Bool {
        guard isValidBranchName(branch) else { return false }
        let destination: String?
        if let remote { destination = remote } else {
            destination = try? await repositoryContext(in: directory, baseBranch: branch).baseRemote
        }
        guard let remote = destination, (try? validate(ref: remote, label: "remote")) != nil else { return false }
        let refspec = "+refs/heads/\(branch):refs/remotes/\(remote)/\(branch)"
        let result = try? await runAgainstRemote(
            ["fetch", "--no-tags", "--", remote, refspec], in: directory, timeout: timeout
        )
        return result?.ok ?? false
    }

    public static func fetchBranches(
        from remote: String, in directory: String, timeout: Duration = .seconds(20)
    ) async -> Bool {
        guard (try? validate(ref: remote, label: "remote")) != nil else { return false }
        let refspec = "+refs/heads/*:refs/remotes/\(remote)/*"
        let result = try? await runAgainstRemote(
            ["fetch", "--no-tags", "--prune", "--", remote, refspec], in: directory, timeout: timeout
        )
        return result?.ok ?? false
    }

    public static func revision(of ref: String, in directory: String) async -> String? {
        guard !ref.isEmpty, !ref.hasPrefix("-"), !ref.contains("\0") else { return nil }
        guard let result = try? await run(["rev-parse", "--verify", "\(ref)^{commit}"], in: directory),
              result.ok, !result.trimmed.isEmpty else { return nil }
        return result.trimmed
    }

    public static func baseRevision(
        branch: String, in directory: String
    ) async throws -> (revision: String, base: ContinuationBase) {
        try validate(branch: branch)
        let context = try await repositoryContext(in: directory, baseBranch: branch)
        let fetched = if let remote = context.baseRemote {
            await fetch(context.baseBranch, in: directory, remote: remote)
        } else { false }

        if let tracking = context.baseTrackingRef,
           let revision = await revision(of: tracking, in: directory) {
            return (revision, fetched ? .fetched : .cachedRemote)
        }
        if let revision = await revision(of: "refs/heads/\(branch)", in: directory) {
            return (revision, .localBranch)
        }
        throw ShellError(
            command: "git rev-parse \(branch)",
            status: 1,
            stderr: "Unified Dev could not find \(branch) in this repository or on its configured base remote."
        )
    }

    public static func checkoutNewBranch(
        _ branch: String, at revision: String, in directory: String
    ) async throws {
        try validate(branch: branch)
        try validate(ref: revision, label: "revision")
        try await check(["checkout", "-b", branch, revision], in: directory)
    }

    public static func upstream(of branch: String, in directory: String) async throws -> String? {
        try validate(branch: branch)
        let result = try await run(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "\(branch)@{upstream}"],
            in: directory
        )
        guard result.ok, !result.trimmed.isEmpty else { return nil }
        return result.trimmed
    }

    public static func hasRemoteCounterpart(_ branch: String, in directory: String) async -> Bool {
        guard isValidBranchName(branch) else { return false }
        guard let result = try? await run(
            ["for-each-ref", "--format=%(refname:short)", "refs/remotes"], in: directory
        ), result.ok else { return false }

        return result.lines.contains { ref in
            ref.hasSuffix("/" + branch)
        }
    }

    public static func hasOperationInProgress(in directory: String) async -> Bool {
        let markers = [
            "rebase-merge", "rebase-apply", "MERGE_HEAD",
            "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG",
        ]
        let arguments = ["rev-parse"] + markers.flatMap { ["--git-path", $0] }
        guard let result = try? await run(arguments, in: directory), result.ok else { return false }

        return result.lines.contains { line in
            let path = line.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return false }
            let absolute = path.hasPrefix("/")
                ? path
                : (directory as NSString).appendingPathComponent(path)
            return FileManager.default.fileExists(atPath: absolute)
        }
    }
}

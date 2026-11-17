import Foundation

extension Git {
    public static func changedFiles(
        worktree: String, base: String, scope: DiffScope = .all
    ) async throws -> [ChangedFile] {
        let mergeBase = try await revision(for: scope, base: base, in: worktree)

        async let nameStatusRead = checkRaw(
            ["diff", "--name-status", "-M", "-z", mergeBase, "--"], in: worktree
        )
        async let numstatRead = checkRaw(
            ["diff", "--numstat", "-M", "-z", mergeBase, "--"], in: worktree
        )
        async let untrackedRead = checkRaw(
            ["ls-files", "--others", "--exclude-standard", "-z"], in: worktree
        )

        let nameStatus = try await nameStatusRead
        let numstat = try await numstatRead
        let untracked = try await untrackedRead

        let changeByPath = parseNameStatus(nameStatus.stdout)
        var byPath = parseNumstat(numstat.stdout, changes: changeByPath)
        addUntracked(untracked.stdout, in: worktree, to: &byPath)
        return byPath.values.sorted { $0.path < $1.path }
    }

    private static func addUntracked(_ listing: Data, in worktree: String, to byPath: inout [String: ChangedFile]) {
        for record in nulRecords(listing) {
            let path = String(decoding: record, as: UTF8.self)
            guard !path.isEmpty, byPath[path] == nil else { continue }
            let full = (worktree as NSString).appendingPathComponent(path)
            let lineCount = (try? String(contentsOfFile: full, encoding: .utf8))
                .map(countLines) ?? 0
            byPath[path] = ChangedFile(
                path: path, change: .untracked, additions: lineCount, deletions: 0,
                isBinary: lineCount == 0 && FileManager.default.fileExists(atPath: full)
            )
        }
    }

    static func parseNameStatus(_ data: Data) -> [String: (ChangedFile.Change, String?)] {
        var changes: [String: (ChangedFile.Change, String?)] = [:]
        var records = nulRecords(data)[...]

        while let status = records.popFirst() {
            guard let code = String(decoding: status.prefix(1), as: UTF8.self).first else { continue }
            if code == "R" || code == "C" {
                guard let old = records.popFirst(), let new = records.popFirst() else { break }
                changes[String(decoding: new, as: UTF8.self)] = (
                    code == "R" ? .renamed : .copied, String(decoding: old, as: UTF8.self)
                )
            } else {
                guard let path = records.popFirst() else { break }
                changes[String(decoding: path, as: UTF8.self)] =
                    (ChangedFile.Change(rawValue: String(code)) ?? .modified, nil)
            }
        }
        return changes
    }

    static func parseNumstat(
        _ data: Data,
        changes: [String: (ChangedFile.Change, String?)]
    ) -> [String: ChangedFile] {
        var files: [String: ChangedFile] = [:]
        var records = nulRecords(data)[...]

        while let record = records.popFirst() {
            let fields = split(record, on: 0x09, limit: 2)
            guard fields.count == 3 else { continue }

            let additions = String(decoding: fields[0], as: UTF8.self)
            let deletions = String(decoding: fields[1], as: UTF8.self)

            var path = String(decoding: fields[2], as: UTF8.self)
            var oldPath: String?
            if fields[2].isEmpty {
                guard let old = records.popFirst(), let new = records.popFirst() else { break }
                oldPath = String(decoding: old, as: UTF8.self)
                path = String(decoding: new, as: UTF8.self)
            }

            let recorded = changes[path]
            files[path] = ChangedFile(
                path: path,
                oldPath: recorded?.1 ?? oldPath,
                change: recorded?.0 ?? (oldPath == nil ? .modified : .renamed),
                additions: Int(additions) ?? 0,
                deletions: Int(deletions) ?? 0,
                isBinary: additions == "-"
            )
        }
        return files
    }

    public static func diffStat(worktree: String, base: String) async throws -> (files: Int, additions: Int, deletions: Int) {
        let mergeBase = try await baseline(base, in: worktree)
        async let numstatRead = checkRaw(
            ["diff", "--numstat", "-M", "-z", mergeBase, "--"], in: worktree
        )
        async let untrackedRead = checkRaw(
            ["ls-files", "--others", "--exclude-standard", "-z"], in: worktree
        )
        let numstat = try await numstatRead
        let untracked = try await untrackedRead
        var byPath = parseNumstat(numstat.stdout, changes: [:])
        addUntracked(untracked.stdout, in: worktree, to: &byPath)
        let files = Array(byPath.values)
        return (
            files.count,
            files.reduce(0) { $0 + $1.additions },
            files.reduce(0) { $0 + $1.deletions }
        )
    }

    public static func patch(
        worktree: String, base: String, file: ChangedFile, scope: DiffScope = .all,
        context: Int? = nil
    ) async throws -> String {
        let patchOptions = patchOptions + (context.map { ["-U\($0)"] } ?? [])
        if file.change == .untracked {
            let result = try await run(
                ["diff", "--no-index"] + patchOptions + ["--", "/dev/null", file.path], in: worktree
            )
            guard result.status == 0 || result.status == 1,
                  !(result.status == 1 && result.stdout.isEmpty && !result.stderr.isEmpty) else {
                throw error(["diff", "--no-index"], result.status, result.stderr, result.stdout)
            }
            return result.stdout
        }
        let mergeBase = try await revision(for: scope, base: base, in: worktree)
        return try await check(
            literalPaths(["diff"] + patchOptions + ["-M", mergeBase, "--"] + pathspecs(of: file)), in: worktree
        ).stdout
    }

    public static func patch(worktree: String, base: String, files: [ChangedFile]) async throws -> String {
        let mergeBase = try await baseline(base, in: worktree)
        var whole = try await check(["diff"] + patchOptions + ["-M", mergeBase, "--"], in: worktree).stdout
        for file in files where file.change == .untracked && !file.path.hasSuffix("/") {
            whole += try await patch(worktree: worktree, base: base, file: file)
        }
        return whole
    }

    static func pathspecs(of file: ChangedFile) -> [String] {
        guard let oldPath = file.oldPath, file.change == .renamed else { return [file.path] }
        return [oldPath, file.path]
    }

    private static let patchOptions = [
        "--no-color", "--no-ext-diff", "--no-textconv", "--src-prefix=a/", "--dst-prefix=b/",
    ]

    static func revision(
        for scope: DiffScope, base: String, in worktree: String
    ) async throws -> String {
        guard scope != .all else { return try await baseline(base, in: worktree) }
        let revision = scope.revision(baseline: "")
        try validate(ref: revision, label: "revision")
        return revision
    }

    public static func branchCommits(
        worktree: String, base: String, limit: Int = BranchCommitList.limit
    ) async throws -> BranchCommitList {
        let mergeBase = try await baseline(base, in: worktree)
        let format = "--pretty=format:%H\u{1f}%s\u{1f}%an\u{1f}%aI"
        let output = try await checkRaw(
            [
                "log", "--no-merges", "-z", "--max-count=\(limit + 1)", format,
                "\(mergeBase)..HEAD", "--",
            ],
            in: worktree
        )
        let parsed = parseBranchCommits(output.stdout)
        return BranchCommitList(
            commits: Array(parsed.prefix(limit)), isTruncated: parsed.count > limit
        )
    }

    static func parseBranchCommits(_ data: Data) -> [BranchCommit] {
        nulRecords(data).compactMap { record in
            let fields = record.split(separator: 0x1f, omittingEmptySubsequences: false)
            guard fields.count == 4 else { return nil }
            let sha = String(decoding: fields[0], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sha.isEmpty else { return nil }
            guard let date = try? Date.ISO8601FormatStyle().parse(
                String(decoding: fields[3], as: UTF8.self)
            ) else { return nil }
            return BranchCommit(
                sha: sha,
                subject: String(decoding: fields[1], as: UTF8.self),
                author: String(decoding: fields[2], as: UTF8.self),
                date: date
            )
        }
    }

    public static func localWork(worktree: String) async throws -> LocalWork {
        let status = try await checkRaw(
            ["status", "--porcelain=v1", "-z", "--branch"], in: worktree
        )
        return parseLocalWork(status.stdout)
    }

    static func parseLocalWork(_ data: Data) -> LocalWork {
        var records = nulRecords(data)[...]
        var work = LocalWork()

        guard let header = records.first,
              String(decoding: header.prefix(2), as: UTF8.self) == "##" else {
            return work
        }
        records.removeFirst()

        let line = String(decoding: header.dropFirst(3), as: UTF8.self)
        work.hasUpstream = line.contains("...")
        if let ahead = line.range(of: "[ahead "),
           let end = line[ahead.upperBound...].firstIndex(where: { $0 == "," || $0 == "]" }) {
            work.unpushedCommits = Int(line[ahead.upperBound..<end]) ?? 0
        }

        while let record = records.popFirst() {
            guard record.count > 3 else { continue }
            let code = String(decoding: record.prefix(2), as: UTF8.self)
            if code == "??" {
                work.untrackedFiles += 1
            } else {
                work.modifiedFiles += 1
                if code.contains("R") || code.contains("C") { _ = records.popFirst() }
            }
        }
        return work
    }

    public static func hasUncommittedChanges(worktree: String) async throws -> Bool {
        !(try await check(["status", "--porcelain"], in: worktree).trimmed.isEmpty)
    }

    public static func isTracked(_ path: String, in worktree: String) async -> Bool {
        guard !path.isEmpty, !path.hasPrefix("-"), !path.contains("\0") else { return false }
        let result = try? await run(
            ["ls-files", "--error-unmatch", "-z", "--", path], in: worktree
        )
        return result?.ok ?? false
    }

    public static func commitsAhead(worktree: String, base: String) async throws -> Int {
        try validate(ref: base, label: "base branch")
        let result = try await check(["rev-list", "--count", "\(base)..HEAD", "--"], in: worktree)
        guard let count = Int(result.trimmed) else {
            throw error(["rev-list", "--count", "\(base)..HEAD"], 0, "unreadable count '\(result.trimmed)'", "")
        }
        return count
    }

    public static func countLines(_ contents: String) -> Int {
        guard !contents.isEmpty else { return 0 }
        var count = contents.reduce(into: 0) { total, character in
            if character == "\n" { total += 1 }
        }
        if contents.hasSuffix("\n") == false { count += 1 }
        return count
    }
}

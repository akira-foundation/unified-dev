import Foundation

struct GitOutput: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: String

    var ok: Bool { status == 0 }
}

public enum Git {
    static func runAgainstRemote(
        _ arguments: [String],
        in directory: String,
        loginDirectory: String? = nil,
        timeout: Duration? = nil
    ) async throws -> ShellResult {
        let login = await GitHub.login(forDirectory: loginDirectory ?? directory)
        let environment = BitbucketCredentialHelper.variables(signedInAs: login)
        return try await run(arguments, in: directory, timeout: timeout, environment: environment)
    }

    @discardableResult
    static func run(
        _ arguments: [String],
        in directory: String,
        stdin: String? = nil,
        timeout: Duration? = nil,
        environment: [String: String] = [:]
    ) async throws -> ShellResult {
        let env = ["GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"]
            .merging(environment) { _, extra in extra }
        return try await Shell.run("git", arguments, cwd: directory, env: env, stdin: stdin, timeout: timeout)
    }

    @discardableResult
    static func check(
        _ arguments: [String],
        in directory: String,
        stdin: String? = nil
    ) async throws -> ShellResult {
        let result = try await run(arguments, in: directory, stdin: stdin)
        guard result.ok else { throw error(arguments, result.status, result.stderr, result.stdout) }
        return result
    }

    static func error(_ arguments: [String], _ status: Int32, _ stderr: String, _ stdout: String) -> ShellError {
        ShellError(
            command: "git " + arguments.joined(separator: " "),
            status: status,
            stderr: stderr.isEmpty ? stdout : stderr
        )
    }

    static func runRaw(_ arguments: [String], in directory: String, input: Data? = nil) async throws -> GitOutput {
        let result = try await Shell.runBytes("git", arguments, cwd: directory, env: [
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_OPTIONAL_LOCKS": "0",
        ], stdin: input)
        return GitOutput(
            status: result.status,
            stdout: result.stdout,
            stderr: String(decoding: result.stderr, as: UTF8.self)
        )
    }

    @discardableResult
    static func checkRaw(_ arguments: [String], in directory: String, input: Data? = nil) async throws -> GitOutput {
        let result = try await runRaw(arguments, in: directory, input: input)
        guard result.ok else {
            throw error(arguments, result.status, result.stderr, String(decoding: result.stdout, as: UTF8.self))
        }
        return result
    }

    public static func isValidBranchName(_ name: String) -> Bool {
        guard !name.isEmpty, name != "HEAD" else { return false }
        guard !name.hasPrefix("-") else { return false }
        guard !name.hasPrefix("/"), !name.hasSuffix("/") else { return false }
        guard !name.hasSuffix(".") else { return false }
        guard !name.contains(".."), !name.contains("@{"), !name.contains("//") else { return false }

        for scalar in name.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F { return false }
            if " ~^:?*[\\".unicodeScalars.contains(scalar) { return false }
        }

        for component in name.components(separatedBy: "/") {
            if component.isEmpty || component.hasPrefix(".") || component.hasSuffix(".lock") {
                return false
            }
        }
        return true
    }

    static func validate(ref: String, label: String = "ref") throws {
        guard !ref.isEmpty, !ref.hasPrefix("-"), !ref.contains("\0") else {
            throw ShellError(
                command: "git",
                status: 128,
                stderr: "refusing to use \(ref.isEmpty ? "an empty" : "the unsafe") \(label) '\(ref)'"
            )
        }
    }

    static func validate(branch: String) throws {
        guard isValidBranchName(branch) else {
            throw ShellError(
                command: "git",
                status: 128,
                stderr: "'\(branch)' is not a valid branch name"
            )
        }
    }

    public static func isRepository(_ path: String) async -> Bool {
        await repositoryAnswer(path) == .repository
    }

    static func repositoryAnswer(
        _ path: String,
        environment: [String: String] = [:]
    ) async -> GitRepositoryAnswer {
        do {
            let result = try await run(
                ["rev-parse", "--is-inside-work-tree"],
                in: path,
                environment: environment.merging(["LC_ALL": "C"]) { _, locale in locale }
            )
            return .from(status: result.status, stdout: result.stdout, stderr: result.stderr, path: path)
        } catch {
            return .from(launchFailure: error)
        }
    }

    public static func topLevel(of path: String) async throws -> String {
        try await check(["rev-parse", "--show-toplevel"], in: path).trimmed
    }

    public static func defaultBranch(of repo: String) async throws -> String {
        if let announced = await remoteDefaultBranch(of: repo) { return announced }
        let config = try await repositoryConfiguration(in: repo)
        let branch = try await currentBranch(of: repo) ?? "HEAD"
        return try await defaultBase(config: config, current: branch, in: repo)
    }

    public static func currentBranch(of path: String) async throws -> String? {
        let result = try await run(["rev-parse", "--abbrev-ref", "HEAD"], in: path)
        guard result.ok else { return nil }
        let branch = result.trimmed
        return branch == "HEAD" ? nil : branch
    }

    public static func branches(of repo: String) async throws -> [String] {
        try await check(["for-each-ref", "--format=%(refname:short)", "refs/heads"], in: repo).lines
    }

    public static func branchExists(_ branch: String, in repo: String) async -> Bool {
        guard isValidBranchName(branch) else { return false }
        let result = try? await run(["show-ref", "--verify", "--quiet", "--", "refs/heads/\(branch)"], in: repo)
        return result?.ok ?? false
    }

    public static func headSHA(of path: String) async throws -> String {
        try await check(["rev-parse", "HEAD"], in: path).trimmed
    }

    public static func mergeBase(_ base: String, _ head: String = "HEAD", in path: String) async throws -> String {
        try validate(ref: base, label: "base branch")
        try validate(ref: head, label: "revision")
        let result = try await run(["merge-base", base, head], in: path)
        if result.ok, !result.trimmed.isEmpty { return result.trimmed }
        return try await check(["rev-parse", "--verify", "\(base)^{commit}"], in: path).trimmed
    }

    public static func isAncestor(
        _ ancestor: String, of descendant: String, in path: String
    ) async -> Bool {
        guard (try? validate(ref: ancestor, label: "revision")) != nil,
              (try? validate(ref: descendant, label: "revision")) != nil
        else { return false }
        let result = try? await run(
            ["merge-base", "--is-ancestor", ancestor, descendant], in: path
        )
        return result?.ok ?? false
    }

    public static func baseline(_ base: String, in worktree: String) async throws -> String {
        try validate(ref: base, label: "base branch")

        let context = try await repositoryContext(in: worktree, baseBranch: base)
        guard let refs = await refPositions(context, in: worktree) else {
            return try await resolveBaseline(context, in: worktree)
        }

        return try await BaselineCache.shared.baseline(
            worktree: worktree, base: base, fingerprint: refs
        ) {
            try await resolveBaseline(context, in: worktree)
        }
    }

    private static func refPositions(_ context: GitRepositoryContext, in worktree: String) async -> String? {
        let arguments = ["rev-parse", "--revs-only", "HEAD", context.baseBranch]
            + [context.baseTrackingRef].compactMap { $0 }
        guard let result = try? await run(arguments, in: worktree), result.ok else { return nil }
        return BaselineFingerprint.make(result.stdout)
    }

    private static func resolveBaseline(_ context: GitRepositoryContext, in worktree: String) async throws -> String {
        let base = context.baseBranch
        let local = base == context.publishBranch ? nil : try? await mergeBase(base, in: worktree)

        guard let tracking = context.baseTrackingRef,
              await revision(of: tracking, in: worktree) != nil,
              let remoteSide = try? await mergeBase(tracking, in: worktree)
        else {
            if let local { return local }
            return try await mergeBase(base, in: worktree)
        }

        guard let local else { return remoteSide }
        guard local != remoteSide else { return local }
        return await isAncestor(local, of: remoteSide, in: worktree) ? remoteSide : local
    }

    static func nulRecords(_ data: Data) -> [Data] {
        var records: [Data] = []
        var start = data.startIndex
        for index in data.indices where data[index] == 0 {
            records.append(data[start..<index])
            start = data.index(after: index)
        }
        if start < data.endIndex { records.append(data[start...]) }
        return records
    }

    static func split(_ data: Data, on byte: UInt8, limit: Int) -> [Data] {
        var pieces: [Data] = []
        var start = data.startIndex
        var index = data.startIndex
        while index < data.endIndex, pieces.count < limit {
            if data[index] == byte {
                pieces.append(data[start..<index])
                start = data.index(after: index)
            }
            index = data.index(after: index)
        }
        pieces.append(data[start...])
        return pieces
    }
}

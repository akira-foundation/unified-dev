import Foundation

public enum Bitbucket {
    public static let executable = "bkt"
    public static let notInstalledMessage = "Install the Bitbucket CLI (bkt) to refresh pull requests."
    public static let signedOutMessage = "Sign in to Bitbucket with bkt to refresh pull requests."
    static let appContext = "unifieddev"
    static let notFound = "404 Not Found"
    static let refusals = ["401 Unauthorized", "403 Forbidden", notFound]

    @TaskLocal static var commandOverride: (@Sendable ([String], String?) async throws -> ShellResult)?

    private struct ReadingKey: Hashable, Sendable {
        let path: String
        let branch: String
        let number: Int?
    }

    private static let readings = SharedReadings<ReadingKey, PullRequestSnapshot?>()

    public static func readingIfHosted(for workspace: Workspace, maxAge: Duration) async -> PullRequestReading? {
        guard await Forge.kind(forDirectory: workspace.path) == .bitbucket else { return nil }
        return await readPullRequestAndChecks(for: workspace, maxAge: maxAge)
    }

    public static func readPullRequestAndChecks(for workspace: Workspace, maxAge: Duration) async -> PullRequestReading {
        do {
            return PullRequestReading(try await snapshot(for: workspace, maxAge: maxAge))
        } catch {
            var unread = Self.failure(error)
            unread.forge = .bitbucket
            return PullRequestReading(pullRequest: .unavailable(unread), checks: nil)
        }
    }

    static func snapshot(for workspace: Workspace, maxAge: Duration) async throws -> PullRequestSnapshot? {
        guard let checkout = await Forge.checkout(forDirectory: workspace.path),
              let repository = checkout.base, repository.kind == .bitbucket else {
            throw GitHubReadFailure(reason: .unavailable, message: "This workspace has no Bitbucket remote.")
        }
        let own = Set(checkout.remotes.filter { $0.kind == .bitbucket }.map(\.fullName))
        let head = await GitHub.headBranch(of: workspace)
        let key = ReadingKey(path: workspace.path, branch: head, number: workspace.pullRequestNumber)
        return try await readings.value(for: key, notOlderThan: maxAge) {
            let context = try await session(in: workspace.path, for: repository)
            guard let payload = try await pullRequest(
                of: workspace, onBranch: head, in: repository, ownRepositories: own, context: context
            ) else { return nil }
            let statuses = try await statuses(
                of: payload.source?.commit?.hash, in: repository, context: context, directory: workspace.path
            )
            var runs = statuses
            if let statuses {
                runs = await withPipelineSteps(statuses, in: repository, context: context, directory: workspace.path)
            }
            return PullRequestSnapshot(pullRequest: payload.pullRequest(runs: runs), runs: runs ?? [])
        }
    }

    static func choose(
        _ found: [BitbucketPullRequestPayload], createdAt: Date, ownRepositories: Set<String> = []
    ) -> BitbucketPullRequestPayload? {
        let candidates = found.filter { candidate in
            guard candidate.isFromFork == true else { return true }
            return candidate.sourceRepository.map { ownRepositories.contains($0.lowercased()) } ?? false
        }
        if let open = candidates.first(where: { $0.unifiedState == "OPEN" }) { return open }
        return candidates.first { candidate in
            guard let closed = BitbucketDates.parse(candidate.updatedOn) else { return false }
            return closed >= createdAt
        }
    }

    static func session(in directory: String, for repository: ForgeRepository) async throws -> String {
        if commandOverride == nil {
            await LoginShellPath.ready()
            guard Shell.which(executable) != nil else {
                throw GitHubReadFailure(reason: .unavailable, message: notInstalledMessage)
            }
        }
        let result = try await run(["auth", "status", "--json"], directory: directory)
        guard result.ok, let status = BitbucketAuthStatus.decode(result.stdout) else {
            throw shellError(["auth", "status", "--json"], result: result)
        }
        guard status.isSignedInToCloud else {
            throw GitHubReadFailure(reason: .authentication, message: signedOutMessage)
        }
        if let context = status.cloudContext { return context }
        let create = [
            "context", "create", appContext,
            "--host", BitbucketAuthStatus.cloudHostKey, "--workspace", repository.owner,
        ]
        let created = try await run(create, directory: directory)
        guard created.ok else { throw shellError(create, result: created) }
        return appContext
    }

    static func pullRequestQueryArguments(
        branch: String, in repository: ForgeRepository, context: String
    ) -> [String] {
        let escaped = branch
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return [
            "api", "\(path(of: repository))/pullrequests",
            "--param", "q=source.branch.name=\"\(escaped)\"",
            "--param", "state=OPEN", "--param", "state=MERGED", "--param", "state=DECLINED",
            "--param", "sort=-updated_on", "--param", "pagelen=50",
            "--context", context,
        ]
    }

    static func statusArguments(commit: String, in repository: ForgeRepository, context: String) -> [String] {
        [
            "api", "\(path(of: repository))/commit/\(commit)/statuses",
            "--param", "pagelen=100", "--context", context,
        ]
    }

    static func decodeStatuses(_ output: String) throws -> [CheckRun] {
        try decode(BitbucketPage<BitbucketCommitStatusPayload>.self, from: output).values.map(\.checkRun)
    }

    static func decodePullRequests(_ output: String) throws -> [BitbucketPullRequestPayload] {
        try decode(BitbucketPage<BitbucketPullRequestPayload>.self, from: output).values
    }

    static func decodePullRequest(_ output: String) throws -> BitbucketPullRequestPayload {
        try decode(BitbucketPullRequestPayload.self, from: output)
    }

    static func failure(_ error: Error) -> GitHubReadFailure {
        if let failure = error as? GitHubReadFailure { return failure }
        let message = String(describing: error)
        let lower = ((error as? ShellError)?.stderr ?? message).lowercased()
        let authentication = ["401 unauthorized", "bkt auth login", "token expired"].contains(where: lower.contains)
        return GitHubReadFailure(
            reason: authentication ? .authentication : .unavailable,
            message: authentication ? signedOutMessage : String(message.prefix(1_000))
        )
    }

    private static func pullRequest(
        of workspace: Workspace, onBranch head: String, in repository: ForgeRepository,
        ownRepositories: Set<String>, context: String
    ) async throws -> BitbucketPullRequestPayload? {
        let found = try await pullRequest(
            onBranch: head, in: repository, context: context, directory: workspace.path
        )
        if let chosen = found.flatMap({ choose($0, createdAt: workspace.createdAt, ownRepositories: ownRepositories) }) { return chosen }
        guard let number = workspace.pullRequestNumber else { return nil }
        return try await pullRequest(number: number, in: repository, context: context, directory: workspace.path)
    }

    private static func pullRequest(
        onBranch branch: String, in repository: ForgeRepository, context: String, directory: String
    ) async throws -> [BitbucketPullRequestPayload]? {
        guard Git.isValidBranchName(branch) else { return nil }
        let arguments = pullRequestQueryArguments(branch: branch, in: repository, context: context)
        let result = try await run(arguments, directory: directory)
        guard result.ok else { throw shellError(arguments, result: result) }
        return try decodePullRequests(result.stdout)
    }

    private static func pullRequest(
        number: Int, in repository: ForgeRepository, context: String, directory: String
    ) async throws -> BitbucketPullRequestPayload? {
        guard number > 0 else { return nil }
        let arguments = ["api", "\(path(of: repository))/pullrequests/\(number)", "--context", context]
        let result = try await run(arguments, directory: directory)
        guard result.ok else {
            if printedStatus(of: result)?.hasPrefix(notFound) == true { return nil }
            throw shellError(arguments, result: result)
        }
        return try decodePullRequest(result.stdout)
    }

    private static func statuses(
        of commit: String?, in repository: ForgeRepository, context: String, directory: String
    ) async throws -> [CheckRun]? {
        guard let commit, !commit.isEmpty, commit.allSatisfy(\.isHexDigit) else { return nil }
        let arguments = statusArguments(commit: commit, in: repository, context: context)
        let result = try await run(arguments, directory: directory)
        guard result.ok else {
            let status = printedStatus(of: result) ?? ""
            if refusals.contains(where: status.hasPrefix) { return nil }
            throw shellError(arguments, result: result)
        }
        return try decodeStatuses(result.stdout)
    }

    static func printedStatus(of result: ShellResult) -> String? {
        (result.stderr + "\n" + result.stdout)
            .split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("Error: ") }
            .map { String($0.dropFirst("Error: ".count)) }
    }

    static func path(of repository: ForgeRepository) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let owner = repository.owner.addingPercentEncoding(withAllowedCharacters: allowed) ?? repository.owner
        let name = repository.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? repository.name
        return "/repositories/\(owner)/\(name)"
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from output: String) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: Data(output.utf8))
        } catch {
            throw GitHubReadFailure(reason: .unavailable, message: "Could not decode bkt JSON: \(error)")
        }
    }

    static func run(
        _ arguments: [String], directory: String, timeout: Duration = .seconds(20), login chosen: BitbucketLogin? = nil
    ) async throws -> ShellResult {
        if let commandOverride { return try await commandOverride(arguments, directory) }
        let login: BitbucketLogin
        if let chosen { login = chosen } else { login = await GitHub.login(forDirectory: directory).bitbucket }
        let env = BitbucketCredentialHelper.variables(adding: login.variables)
        return try await Shell.run(executable, arguments, cwd: directory, env: env, timeout: timeout)
    }

    static func connection(in directory: String) async throws -> (repository: ForgeRepository, context: String) {
        guard let repository = await Forge.repository(forDirectory: directory), repository.kind == .bitbucket else {
            throw GitHubReadFailure(reason: .unavailable, message: "This checkout has no Bitbucket remote.")
        }
        return (repository, try await session(in: directory, for: repository))
    }

    static func shellError(_ arguments: [String], result: ShellResult) -> ShellError {
        ShellError(
            command: "\(executable) " + arguments.joined(separator: " "),
            status: result.status,
            stderr: result.stderr.isEmpty ? result.stdout : result.stderr
        )
    }
}

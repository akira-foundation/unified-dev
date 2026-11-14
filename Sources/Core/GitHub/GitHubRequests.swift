import Foundation
import Synchronization

actor GitHubRequests {
    struct Key: Hashable, Sendable {
        let host: String
        let directory: String?
        let arguments: [String]
        var login: GitHubLogin = .thisMac

        var limitedHost: String {
            login.directory.map { host + "\n" + $0.path } ?? host
        }
    }
    private struct Flight {
        let id: UUID
        let task: Task<ShellResult, Error>
    }
    private var flights: [Key: Flight] = [:]
    private let limits = GitHubRateLimits()
    private(set) var activeSubscribers = 0

    func run(
        key: Key, interactive: Bool,
        execute: @escaping @Sendable () async throws -> ShellResult
    ) async throws -> ShellResult {
        try Task.checkCancellation()
        if !interactive, let flight = flights[key] {
            return try await wait(for: flight.task)
        }
        let lease = try await limits.check(host: key.limitedHost, interactive: interactive)
        try Task.checkCancellation()
        if !interactive, let flight = flights[key] {
            return try await wait(for: flight.task)
        }
        let id = UUID()
        let task = Task { [limits] in
            let result = try await execute()
            if !result.ok && GitHubReadFailure.isRateLimit(result.stderr + result.stdout) {
                let retryAt = await limits.limited(
                    host: key.limitedHost, lease: lease,
                    retryAt: GitHubReadFailure.retryDate(from: result.stderr, now: Date())
                )
                throw GitHubReadFailure(
                    reason: .rateLimited, message: "GitHub's rate limit was reached. Refresh will resume automatically.",
                    retryAt: retryAt
                )
            }
            if result.ok { await limits.succeeded(host: key.limitedHost, lease: lease) }
            return result
        }
        if !interactive {
            flights[key] = Flight(id: id, task: task)
            Task { [weak self] in
                _ = try? await task.value
                await self?.completed(key: key, id: id)
            }
        }
        return try await wait(for: task)
    }

    private func wait(for task: Task<ShellResult, Error>) async throws -> ShellResult {
        activeSubscribers += 1
        defer { activeSubscribers -= 1 }
        return try await GitHubRequestWaiter.value(of: task)
    }

    private func completed(key: Key, id: UUID) {
        if flights[key]?.id == id { flights[key] = nil }
    }
}

extension GitHub {
    private static let requests = GitHubRequests()
    @TaskLocal static var commandOverride: (@Sendable ([String], String?) async throws -> ShellResult)?
    @TaskLocal public static var login: GitHubLogin?
    @TaskLocal static var loginResolverOverride: (@Sendable (String) async -> GitHubLogin?)?
    private static let loginResolver = Mutex<(@Sendable (String) async -> GitHubLogin?)?>(nil)

    public static func adoptLoginResolver(_ resolve: @escaping @Sendable (String) async -> GitHubLogin?) {
        loginResolver.withLock { $0 = resolve }
    }

    public static func login(forDirectory directory: String?) async -> GitHubLogin {
        if let login { return login }
        guard let directory, let resolve = loginResolverOverride ?? loginResolver.withLock({ $0 }) else {
            return .thisMac
        }
        return await resolve(directory) ?? .thisMac
    }

    static func run(
        _ executable: String, _ arguments: [String] = [], cwd: String? = nil,
        timeout: Duration = .seconds(20), repositoryContext: GitRepositoryContext? = nil
    ) async throws -> ShellResult {
        guard executable == "gh" else {
            let login = await login(forDirectory: cwd)
            return try await Shell.run(executable, arguments, cwd: cwd, env: login.variables, timeout: timeout)
        }
        let context: GitRepositoryContext?
        if let repositoryContext { context = repositoryContext } else {
            context = await readContext(arguments: arguments, cwd: cwd)
        }
        let action = arguments.dropFirst().first ?? ""
        let interactive = ["create", "edit", "merge", "checkout", "delete"].contains(action)
        let resolved = repositoryArguments(arguments, context: context)
        let host = requestHost(arguments: resolved, context: context)
        let command = commandOverride
        let login = await login(forDirectory: cwd)
        return try await requests.run(
            key: .init(host: host, directory: cwd, arguments: resolved, login: login), interactive: interactive
        ) {
            if let command { return try await $login.withValue(login) { try await command(resolved, cwd) } }
            return try await Shell.run(executable, resolved, cwd: cwd, env: login.variables, timeout: timeout)
        }
    }

    static func readContext(arguments: [String], cwd: String?) async -> GitRepositoryContext? {
        guard let cwd else { return nil }
        let base = arguments.firstIndex(of: "--base").flatMap { index in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        }
        let branch: String? = if arguments.count > 2, arguments[0] == "pr", arguments[1] == "view",
                                Git.isValidBranchName(arguments[2]), Int(arguments[2]) == nil {
            arguments[2]
        } else { nil }
        return try? await Git.repositoryContext(in: cwd, baseBranch: base, branch: branch)
    }

    static func requestHost(arguments: [String], context: GitRepositoryContext?) -> String {
        if let repository = repositoryOption(in: arguments) {
            let pieces = repository.split(separator: "/")
            if pieces.count == 3 { return String(pieces[0]).lowercased() }
        }
        if let url = arguments.compactMap({ URL(string: $0) }).first(where: { $0.scheme == "https" || $0.scheme == "http" }),
           let host = url.host { return host.lowercased() }
        return repositoryHost(context?.baseRemoteURL) ?? ProcessInfo.processInfo.environment["GH_HOST"] ?? "github.com"
    }

    private static func repositoryOption(in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == "--repo" || argument == "-R", arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
            if argument.hasPrefix("--repo=") { return String(argument.dropFirst(7)) }
            if argument.hasPrefix("-R"), argument.count > 2 { return String(argument.dropFirst(2)) }
        }
        return nil
    }

    static func repositoryArguments(_ arguments: [String], context: GitRepositoryContext?) -> [String] {
        let family = arguments.first ?? ""
        let action = arguments.dropFirst().first ?? ""
        let acceptsRepo = family == "pr" || (family == "run" && action == "view") || (family == "issue" && action == "list")
        guard acceptsRepo, !isUnselectedPullRequestView(arguments),
              repositoryOption(in: arguments) == nil,
              !arguments.contains("--repo"), !arguments.contains("-R"),
              let context, let base = repositorySpecifier(context.baseRemoteURL) else { return arguments }
        var result = arguments
        if family == "pr", result.count > 2, result[1] == "view", !result[2].hasPrefix("-"),
           Int(result[2]) == nil, !result[2].contains(":") {
            result[2] = PullRequestHead.label(
                result[2], of: context.headRemoteURL, base: context.baseRemoteURL
            )
        }
        if family == "pr", action == "create", !result.contains("--head"),
           context.headBranch != "HEAD",
           let owner = PullRequestHead.owner(
               of: context.headRemoteURL, otherThan: context.baseRemoteURL
           ) {
            result += ["--head", "\(owner):\(context.headBranch)"]
        }
        result += ["--repo", base]
        return result
    }

    private static func isUnselectedPullRequestView(_ arguments: [String]) -> Bool {
        guard arguments.first == "pr", arguments.dropFirst().first == "view" else { return false }
        return arguments.dropFirst(2).first?.hasPrefix("-") ?? true
    }

    static func repositorySpecifier(_ remote: String?) -> String? {
        guard let remote, let host = repositoryHost(remote),
              let path = repositoryPath(of: remote) else { return nil }
        var pieces = path.split(separator: "/").map(String.init)
        guard pieces.count == 2 else { return nil }
        if pieces[1].hasSuffix(".git") { pieces[1].removeLast(4) }
        guard pieces.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("-") }) else { return nil }
        return "\(host)/\(pieces[0])/\(pieces[1])"
    }

    private static func repositoryPath(of remote: String) -> String? {
        if let url = URL(string: remote), url.host != nil { return url.path }
        guard let colon = remote.firstIndex(of: ":") else { return nil }
        return String(remote[remote.index(after: colon)...])
    }

    static func repositoryHost(_ remote: String?) -> String? {
        guard let remote else { return nil }
        if let host = URL(string: remote)?.host { return host.lowercased() }
        if let at = remote.firstIndex(of: "@"), let colon = remote[at...].firstIndex(of: ":") {
            return String(remote[remote.index(after: at)..<colon]).lowercased()
        }
        return nil
    }
}

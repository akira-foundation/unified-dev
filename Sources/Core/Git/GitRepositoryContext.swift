import Foundation

public struct GitRepositoryContext: Sendable, Equatable {
    public let baseBranch: String
    public let baseRemote: String?
    public let publishBranch: String
    public let publishRemote: String?
    public let baseRemoteURL: String?
    public let publishRemoteURL: String?
    public let headBranch: String
    public let headRemoteURL: String?
    public let remoteURLs: [String]
    public let headIsTracked: Bool

    public var baseTrackingRef: String? {
        baseRemote.map { "refs/remotes/\($0)/\(baseBranch)" }
    }

    public var publishTrackingRef: String? {
        publishRemote.map { "refs/remotes/\($0)/\(publishBranch)" }
    }

    static func resolve(
        config: [String: String], base: String, branch: String, baseIsBranchName: Bool = false
    ) -> Self {
        let remotes = config.keys.compactMap { key -> String? in
            guard key.hasPrefix("remote."), key.hasSuffix(".url") else { return nil }
            return String(key.dropFirst(7).dropLast(4))
        }.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        let primary = remotes.contains("origin") ? "origin" : remotes.min()
        let qualified = base.hasPrefix("refs/remotes/")
        let given = qualified ? String(base.dropFirst(13)) : base
        let recorded = config["branch.\(branch).unifieddev-base-remote"]
        let explicitRemote = splittingRemote(
            of: given, qualified: qualified, plainBranch: baseIsBranchName, recorded: recorded, remotes: remotes
        )
        let baseBranch = explicitRemote.map { String(given.dropFirst($0.count + 1)) } ?? given
        let configuredBase = config["branch.\(baseBranch).remote"]
        let currentRemote = config["branch.\(branch).remote"]
        let merge = config["branch.\(branch).merge"]
        let baseRemote = explicitRemote ?? recorded ?? configuredBase ?? currentRemote ?? primary
        let branchPushRemote = config["branch.\(branch).pushremote"]
        let explicitPublication = branchPushRemote ?? config["remote.pushdefault"]
        let publishRemote = explicitPublication
            ?? ((merge?.hasPrefix("refs/pull/") ?? false) ? nil
                : ((merge == "refs/heads/\(branch)" ? currentRemote : nil) ?? primary))
        let trackedHead = merge.flatMap { reference -> String? in
            guard reference.hasPrefix("refs/heads/") else { return nil }
            let name = String(reference.dropFirst(11))
            guard !name.isEmpty, name != baseBranch else { return nil }
            return name
        }
        let headRemote = branchPushRemote
            ?? (trackedHead == nil ? publishRemote : (currentRemote ?? publishRemote))
        return Self(
            baseBranch: baseBranch,
            baseRemote: baseRemote == "." ? nil : baseRemote,
            publishBranch: branch,
            publishRemote: publishRemote == "." ? nil : publishRemote,
            baseRemoteURL: baseRemote.flatMap { config["remote.\($0).url"] },
            publishRemoteURL: publishRemote.flatMap { config["remote.\($0).pushurl"] ?? config["remote.\($0).url"] },
            headBranch: trackedHead ?? branch,
            headRemoteURL: headRemote.flatMap { config["remote.\($0).pushurl"] ?? config["remote.\($0).url"] },
            remoteURLs: remotes.compactMap { config["remote.\($0).url"] }.sorted(),
            headIsTracked: trackedHead != nil || branchPushRemote != nil
        )
    }

    static func namesABranch(
        _ base: String, localBranches: Set<String>, remoteReferences: [String], remoteNames: [String]
    ) -> Bool {
        if localBranches.contains(base) { return true }
        guard let primary = Git.primaryRemote(of: remoteNames) else { return true }
        return remoteReferences.contains("\(primary)/\(base)")
    }

    private static func splittingRemote(
        of given: String, qualified: Bool, plainBranch: Bool, recorded: String?, remotes: [String]
    ) -> String? {
        if qualified { return remotes.first { given.hasPrefix($0 + "/") } }
        if plainBranch { return nil }
        guard let recorded else { return remotes.first { given.hasPrefix($0 + "/") } }
        return given.hasPrefix(recorded + "/") ? recorded : nil
    }
}

extension Git {
    public static func remoteNames(of directory: String) async throws -> [String] {
        try await check(["remote"], in: directory).lines
    }

    static func primaryRemote(of names: [String]) -> String? {
        names.contains(remote) ? remote : names.min()
    }

    static func recordBase(_ context: GitRepositoryContext, for branch: String, in directory: String) async throws {
        try validate(branch: branch)
        try await check(["config", "branch.\(branch).gh-merge-base", context.baseBranch], in: directory)
        if let remote = context.baseRemote {
            try await check(["config", "branch.\(branch).unifieddev-base-remote", remote], in: directory)
        }
    }

    public static func repositoryContext(
        in directory: String, baseBranch: String? = nil, branch: String? = nil, baseIsBranchName: Bool = false
    ) async throws -> GitRepositoryContext {
        let current = try await currentBranchName(given: branch, in: directory)
        let config = try await repositoryConfiguration(in: directory)
        let base = try await baseName(given: baseBranch, config: config, current: current, in: directory)
        try validate(ref: base, label: "base branch")
        if current != "HEAD" { try validate(branch: current) }
        return GitRepositoryContext.resolve(
            config: config, base: base, branch: current, baseIsBranchName: baseBranch == nil || baseIsBranchName
        )
    }

    private static func currentBranchName(given: String?, in directory: String) async throws -> String {
        if let given { return given }
        if let head = headBranch(in: directory) { return head }
        return try await currentBranch(of: directory) ?? "HEAD"
    }

    private static func baseName(
        given: String?, config: [String: String], current: String, in directory: String
    ) async throws -> String {
        if let given { return given }
        if let recorded = config["branch.\(current).gh-merge-base"] { return recorded }
        if let merge = config["branch.\(current).merge"], merge.hasPrefix("refs/heads/"),
           merge != "refs/heads/\(current)" {
            return String(merge.dropFirst(11))
        }
        return try await defaultBase(config: config, current: current, in: directory)
    }

    static func repositoryConfiguration(in directory: String) async throws -> [String: String] {
        let output = try await checkRaw(["config", "--null", "--list", "--includes"], in: directory)
        var config: [String: String] = [:]
        for record in nulRecords(output.stdout) {
            guard let separator = record.firstIndex(of: 10) else { continue }
            let key = String(decoding: record[..<separator], as: UTF8.self)
            config[key] = String(decoding: record[record.index(after: separator)...], as: UTF8.self)
        }
        return config
    }

    static func defaultBase(config: [String: String], current: String, in directory: String) async throws -> String {
        let provisional = GitRepositoryContext.resolve(config: config, base: "main", branch: current)
        if let remote = provisional.baseRemote {
            let prefix = "refs/remotes/\(remote)/"
            let head = try await run(["symbolic-ref", prefix + "HEAD"], in: directory)
            if head.ok, head.trimmed.hasPrefix(prefix) { return String(head.trimmed.dropFirst(prefix.count)) }
        }
        let candidates = ["main", "master", "develop"]
        let names = try await check(
            ["for-each-ref", "--format=%(refname:short)"] + candidates.map { "refs/heads/\($0)" }, in: directory
        ).lines
        return candidates.first(where: { names.contains($0) }) ?? (current == "HEAD" ? "main" : current)
    }
    public static func headBranch(in directory: String) -> String? {
        guard let paths = repositoryPaths(in: directory),
              let head = try? String(contentsOfFile: (paths.gitDirectory as NSString).appendingPathComponent("HEAD"), encoding: .utf8)
        else { return nil }
        let prefix = "ref: refs/heads/"
        guard head.hasPrefix(prefix) else { return "HEAD" }
        return String(head.dropFirst(prefix.count)).trimmingCharacters(in: .newlines)
    }
}

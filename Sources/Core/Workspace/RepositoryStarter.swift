import Foundation

public enum RepositoryDestination: Sendable, Equatable {
    case local
    case gitHub(owner: String, name: String, isPrivate: Bool)

    public var isGitHub: Bool {
        if case .gitHub = self { return true }
        return false
    }

    public var slug: String? {
        guard case .gitHub(let owner, let name, _) = self else { return nil }
        return "\(owner)/\(name)"
    }
}

public enum RepositoryStartStep: String, Sendable, CaseIterable, Comparable {
    case initialise
    case commit
    case createRemoteRepository
    case addOrigin
    case push

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
    }

    public var label: String {
        switch self {
        case .initialise: "Creating the repository"
        case .commit: "Making the first commit"
        case .createRemoteRepository: "Creating the repository on GitHub"
        case .addOrigin: "Adding origin"
        case .push: "Pushing"
        }
    }

    public static func steps(for destination: RepositoryDestination) -> [RepositoryStartStep] {
        destination.isGitHub ? allCases : [.initialise, .commit]
    }

    public var patience: Duration {
        switch self {
        case .initialise: .seconds(15)
        case .commit: .seconds(20)
        case .createRemoteRepository: .seconds(30)
        case .addOrigin: .seconds(15)
        case .push: .seconds(180)
        }
    }

    public var slowNotice: String {
        switch self {
        case .initialise:
            """
            git init has not come back. It is normally instant, so something outside git is \
            holding it up. You can stop and try again.
            """
        case .commit:
            """
            git commit has not come back. The usual cause is commit signing: a key, a smart card \
            or a helper such as 1Password is waiting for an approval, and the prompt can be \
            behind another window or missing altogether. Look for it, or stop and try again.
            """
        case .createRemoteRepository:
            """
            gh has not answered. It may be waiting on the network, or on a login that has to be \
            finished in a browser. You can stop and try again.
            """
        case .addOrigin:
            """
            git remote add has not come back, which is a local command that should be instant. \
            You can stop and try again.
            """
        case .push:
            """
            Still uploading. A first push of a large folder takes a while, so this is not \
            necessarily wrong. Stopping now leaves the commit here and nothing on GitHub.
            """
        }
    }
}

public enum RepositoryStartAbandonment: Sendable, Equatable {
    case nothingToUndo
    case repositoryRemoved
    case projectKept

    public static func decide(hasGitDirectory: Bool, hasCommits: Bool) -> Self {
        guard hasGitDirectory else { return .nothingToUndo }
        return hasCommits ? .projectKept : .repositoryRemoved
    }

    public var isUsableProject: Bool { self == .projectKept }

    public var state: String {
        switch self {
        case .nothingToUndo:
            "Nothing was changed. The folder is exactly as it was."
        case .repositoryRemoved:
            """
            The repository Unified Dev had started making was removed again, so the folder is exactly \
            as it was. Anything the run had already written to .gitignore is still there.
            """
        case .projectKept:
            """
            The folder is a git repository and your files are in its first commit, so Unified Dev can \
            run workspaces in it. Nothing was sent to GitHub.
            """
        }
    }
}

public struct RepositoryStartOutcome: Sendable, Equatable {
    public var branch: String
    public var committedFiles: Int
    public var excluded: [ExcludedPath]
    public var commitWasUnsigned: Bool
    public var remoteURL: String?
    public var page: String?

    public init(
        branch: String,
        committedFiles: Int,
        excluded: [ExcludedPath] = [],
        commitWasUnsigned: Bool = false,
        remoteURL: String? = nil,
        page: String? = nil
    ) {
        self.branch = branch
        self.committedFiles = committedFiles
        self.excluded = excluded
        self.commitWasUnsigned = commitWasUnsigned
        self.remoteURL = remoteURL
        self.page = page
    }
}

public struct RepositoryStartFailure: Error, Sendable, Equatable {
    public var step: RepositoryStartStep
    public var message: String
    public var completed: Set<RepositoryStartStep>
    public var destination: RepositoryDestination
    public var branch: String?

    public init(
        step: RepositoryStartStep,
        message: String,
        completed: Set<RepositoryStartStep>,
        destination: RepositoryDestination,
        branch: String? = nil
    ) {
        self.step = step
        self.message = message
        self.completed = completed
        self.destination = destination
        self.branch = branch
    }

    public var isUsableProject: Bool {
        completed.contains(.initialise) && completed.contains(.commit)
    }

    public var state: String {
        let slug = destination.slug ?? "the repository"

        if !completed.contains(.initialise) {
            return "Nothing was changed. The folder is exactly as it was."
        }
        if !completed.contains(.commit) {
            return """
            The folder is now a git repository, and it has no commits. Unified Dev cannot create a \
            workspace until it has one, because a worktree needs a branch to start from.
            """
        }
        if !completed.contains(.createRemoteRepository) {
            return """
            The folder is a git repository and your files are in its first commit. Nothing was \
            sent to GitHub, and no repository was created there.
            """
        }
        if !completed.contains(.addOrigin) {
            return """
            The folder is a git repository and your files are in its first commit. \(slug) was \
            created on GitHub and is empty. The folder has no origin yet, so nothing has been \
            uploaded.
            """
        }
        return """
        The folder is a git repository and your files are in its first commit. \(slug) was created \
        on GitHub and is empty, and origin points at it. Nothing has been uploaded.
        """
    }

    public var title: String {
        switch step {
        case .initialise: "Could not create the repository"
        case .commit: "Could not make the first commit"
        case .createRemoteRepository: "Could not create the repository on GitHub"
        case .addOrigin: "Could not add origin"
        case .push: "Could not push"
        }
    }
}

public enum RepositoryStarter {
    public static let commitMessage = "Initial commit"

    public static let walkLimit = 50_000

    public static func inspect(
        _ path: String,
        workspacesRoot: String = WorkspaceManager.workspacesRoot.path,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) async -> FolderFacts {
        let manager = FileManager.default
        let expanded = (path as NSString).expandingTildeInPath
        let normalized = FolderPath.normalize(expanded)

        var isDirectory: ObjCBool = false
        let exists = manager.fileExists(atPath: normalized, isDirectory: &isDirectory)

        var answer = GitRepositoryAnswer.notARepository
        if exists, isDirectory.boolValue { answer = await Git.repositoryAnswer(normalized) }
        let isRepository = answer == .repository

        var repositoryRoot: String?
        if isRepository { repositoryRoot = try? await Git.topLevel(of: normalized) }

        return FolderFacts(
            path: normalized,
            isRepository: isRepository,
            repositoryRoot: repositoryRoot,
            enclosingRepository: isRepository ? nil : Git.enclosingRepositoryRoot(of: normalized),
            isWritable: manager.isWritableFile(atPath: normalized),
            isDirectory: exists && isDirectory.boolValue,
            exists: exists,
            isAbsolute: expanded.hasPrefix("/"),
            homeDirectory: home,
            workspacesRoot: workspacesRoot,
            childRepositories: childRepositories(of: normalized),
            gitProblem: answer.problem
        )
    }

    static func childRepositories(of path: String) -> [String] {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(atPath: path) else { return [] }
        return entries.filter { name in
            let child = (path as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: child, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            return manager.fileExists(atPath: (child as NSString).appendingPathComponent(".git"))
        }.sorted()
    }

    public static func scan(_ path: String) -> FolderContents {
        let root = FolderPath.normalize(path)
        let manager = FileManager.default
        var contents = FolderContents()
        contents.hasGitignore = manager.fileExists(
            atPath: (root as NSString).appendingPathComponent(".gitignore")
        )

        guard let walker = manager.enumerator(atPath: root) else { return contents }

        var seen = 0
        while let relative = walker.nextObject() as? String {
            seen += 1
            if seen > walkLimit {
                contents.truncated = true
                break
            }

            let attributes = walker.fileAttributes
            let full = (root as NSString).appendingPathComponent(relative)

            if attributes?[.type] as? FileAttributeType == .typeDirectory {
                if (relative as NSString).lastPathComponent == ".git" {
                    walker.skipDescendants()
                    continue
                }
                if manager.fileExists(atPath: (full as NSString).appendingPathComponent(".git")) {
                    contents.excluded.append(ExcludedPath(path: relative, reason: .nestedRepository))
                    walker.skipDescendants()
                }
                continue
            }

            if (relative as NSString).lastPathComponent == ".git" { continue }

            if SensitiveFile.matches(relative) {
                contents.excluded.append(ExcludedPath(path: relative, reason: .sensitive))
                continue
            }

            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            contents.fileCount += 1
            contents.byteSize += size
            if size >= FolderContents.oversizeLimit { contents.oversizeFiles.append(relative) }
        }
        return contents
    }

    public static func identityProblem(at path: String) async -> String? {
        let identity = await Git.commitIdentity(in: path)
        guard identity.name == nil || identity.email == nil else { return nil }
        return """
        Git does not know who you are on this Mac, so it cannot make a commit. Set a name and an \
        address with git config --global user.name and git config --global user.email, then try \
        again.
        """
    }

    @discardableResult
    public static func start(
        at path: String,
        destination: RepositoryDestination,
        completed: Set<RepositoryStartStep> = [],
        progress: @Sendable @MainActor (RepositoryStartStep) -> Void = { _ in }
    ) async throws -> RepositoryStartOutcome {
        let folder = FolderPath.normalize((path as NSString).expandingTildeInPath)
        var done = completed
        var branch = ""
        var excluded: [ExcludedPath] = []
        var committedFiles = 0
        var unsigned = false

        func fail(_ step: RepositoryStartStep, _ error: Error) -> RepositoryStartFailure {
            RepositoryStartFailure(
                step: step,
                message: sentence(from: error),
                completed: done,
                destination: destination,
                branch: branch.isEmpty ? nil : branch
            )
        }

        if done.contains(.initialise) {
            branch = (try? await Git.check(["symbolic-ref", "--short", "HEAD"], in: folder).trimmed)
                ?? "main"
        } else {
            await progress(.initialise)
            do {
                branch = try await Git.initRepository(at: folder)
            } catch {
                throw fail(.initialise, error)
            }
            done.insert(.initialise)
        }

        if await Git.hasCommits(in: folder) {
            done.insert(.commit)
            committedFiles = (try? await Git.stagedPaths(in: folder).count) ?? 0
        } else {
            await progress(.commit)
            do {
                (committedFiles, excluded, unsigned) = try await makeFirstCommit(in: folder)
            } catch {
                throw fail(.commit, error)
            }
            done.insert(.commit)
        }

        guard case .gitHub(let owner, let name, let isPrivate) = destination else {
            return RepositoryStartOutcome(
                branch: branch,
                committedFiles: committedFiles,
                excluded: excluded,
                commitWasUnsigned: unsigned
            )
        }

        if let existing = await Git.remoteURL("origin", in: folder), !existing.isEmpty {
            done.insert(.createRemoteRepository)
            done.insert(.addOrigin)
        }

        var url = await GitHub.remoteURL(owner: owner, name: name)
        if !done.contains(.createRemoteRepository) {
            await progress(.createRemoteRepository)
            do {
                url = try await GitHub.createRepository(
                    owner: owner, name: name, isPrivate: isPrivate
                )
            } catch {
                throw fail(.createRemoteRepository, error)
            }
            done.insert(.createRemoteRepository)
        }

        if !done.contains(.addOrigin) {
            await progress(.addOrigin)
            do {
                if await Git.remoteURL("origin", in: folder) == nil {
                    try await Git.addRemote("origin", url: url, in: folder)
                }
            } catch {
                throw fail(.addOrigin, error)
            }
            done.insert(.addOrigin)
        }

        if !done.contains(.push) {
            await progress(.push)
            do {
                try await GitHub.push(
                    worktree: folder, branch: branch, setUpstream: true, timeout: .seconds(600)
                )
            } catch {
                throw fail(.push, error)
            }
            done.insert(.push)
        }

        return RepositoryStartOutcome(
            branch: branch,
            committedFiles: committedFiles,
            excluded: excluded,
            commitWasUnsigned: unsigned,
            remoteURL: url,
            page: GitHub.repositoryPage(owner: owner, name: name)
        )
    }

    @discardableResult
    public static func abandon(at path: String) async -> RepositoryStartAbandonment {
        let folder = FolderPath.normalize((path as NSString).expandingTildeInPath)
        let gitDirectory = (folder as NSString).appendingPathComponent(".git")
        let hasGitDirectory = FileManager.default.fileExists(atPath: gitDirectory)

        let hasCommits = hasGitDirectory ? await Git.hasCommits(in: folder) : false
        let outcome = RepositoryStartAbandonment.decide(
            hasGitDirectory: hasGitDirectory, hasCommits: hasCommits
        )
        if outcome == .repositoryRemoved {
            try? FileManager.default.removeItem(atPath: gitDirectory)
        }
        return outcome
    }

    private static func makeFirstCommit(
        in folder: String
    ) async throws -> (files: Int, excluded: [ExcludedPath], unsigned: Bool) {
        let contents = scan(folder)

        let alreadyIgnored = await Git.ignoredPaths(
            among: contents.excluded.map(\.path), in: folder
        )
        let written = contents.excluded.filter { !alreadyIgnored.contains($0.path) }
        if !written.isEmpty { try appendGitignore(written, in: folder) }

        try await Git.stageAll(in: folder)

        let staged = try await Git.stagedPaths(in: folder)
        let forbidden = Set(contents.excluded.map(\.path))
        let leaked = staged.filter { path in
            forbidden.contains(path) || forbidden.contains { path.hasPrefix($0 + "/") }
        }
        if !leaked.isEmpty {
            try await Git.unstage(leaked, in: folder)
        }

        let remaining = try await Git.stagedPaths(in: folder)
        let unsigned = try await Git.commit(
            message: commitMessage, in: folder, allowEmpty: remaining.isEmpty
        )
        return (remaining.count, contents.excluded, unsigned)
    }

    static func appendGitignore(_ paths: [ExcludedPath], in folder: String) throws {
        let url = URL(fileURLWithPath: folder).appendingPathComponent(".gitignore")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        var block = ""
        if !existing.isEmpty && !existing.hasSuffix("\n") { block += "\n" }
        if !existing.isEmpty { block += "\n" }
        block += "# Added by Unified Dev when this folder became a repository.\n"

        let secrets = paths.filter { $0.reason == .sensitive }
        let repositories = paths.filter { $0.reason == .nestedRepository }
        if !secrets.isEmpty {
            block += "# These look like they hold credentials, so they are not committed.\n"
            block += secrets.map(\.gitignoreLine).joined(separator: "\n") + "\n"
        }
        if !repositories.isEmpty {
            block += "# These are git repositories of their own.\n"
            block += repositories.map(\.gitignoreLine).joined(separator: "\n") + "\n"
        }

        try (existing + block).write(to: url, atomically: true, encoding: .utf8)
    }

    public static func output(of error: Error) -> String {
        if let shell = error as? ShellError {
            return shell.stderr.isEmpty ? shell.description : shell.stderr
        }
        return error.readableMessage
    }

    public static func sentence(from error: Error) -> String {
        guard let cause = GitFailureOutput.cause(in: output(of: error)) else { return "It did not say why." }
        return cause.count > 300 ? String(cause.prefix(300)) + "..." : cause
    }
}

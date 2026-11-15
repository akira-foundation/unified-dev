import Foundation
import os

public enum WorkspaceError: Error, CustomStringConvertible {
    case projectFolderMissing
    case recoveryPending
    case notARepository(String)
    case gitCannotRead(GitRepositoryProblem)
    case pathInUse(String)
    case unsafeToArchive(WorkspaceSafetyReport)
    case archiveScriptFailed(status: Int32, output: String)
    case archiveScriptIncomplete(ShellFailure)
    case workspaceGone(String)
    case orchestratorRefused(String)
    case orchestratorHasLiveWork

    public var description: String {
        switch self {
        case .projectFolderMissing: "The project folder is no longer on disk."
        case .recoveryPending: "Resolve the interrupted rewind before removing or archiving this workspace."
        case .notARepository(let path): "\(path) is not a git repository"
        case .gitCannotRead(let problem): problem.sentence
        case .pathInUse(let path): "\(path) already exists"
        case .unsafeToArchive(let report):
            "archiving would permanently destroy " + report.losses.joined(separator: ", ")
        case .archiveScriptFailed(let status, let output):
            "the archive script exited \(status), so nothing was removed: "
                + output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(500)
        case .archiveScriptIncomplete(let failure):
            "The archive script did not finish, so nothing was removed: \(failure.description)"
        case .workspaceGone(let name): "\(name) is no longer in the database"
        case .orchestratorRefused(let sentence): sentence
        case .orchestratorHasLiveWork:
            "An agent is working in this workspace or a chat is open in its terminal, so it cannot become the orchestrator."
        }
    }
}

public struct WorkspaceManager: Sendable {
    public let store: Store
    public let workspacesRoot: URL

    public init(store: Store, workspacesRoot: URL = WorkspaceManager.workspacesRoot) {
        self.store = store
        self.workspacesRoot = workspacesRoot
    }

    public static let workspacesRoot: URL = WorkspacesRoot.resolve()

    private func profileFolder(of repo: Repo) async throws -> String {
        let folders = try await store.profiles().map(\.folder)
        let folder = try await store.profile(id: repo.profileID)?.folder ?? ProfileID.initial.rawValue
        return ProfileFolder.usable(
            folder,
            under: workspacesRoot,
            recordedWorktrees: try await store.workspacePaths(),
            otherProfiles: Set(folders).subtracting([folder])
        )
    }

    @discardableResult
    public func addRepository(at path: String, profileID: ProfileID) async throws -> Repo {
        let expanded = (path as NSString).expandingTildeInPath
        switch await Git.repositoryAnswer(expanded) {
        case .repository: break
        case .notARepository: throw WorkspaceError.notARepository(expanded)
        case .problem(let problem): throw WorkspaceError.gitCannotRead(problem)
        }
        let root = try await Git.topLevel(of: expanded)

        if let existing = try await store.repo(path: root) { return existing }

        let existingRepos = try await store.repos()
        let icon = await Task.detached { RepoIconDetector.detect(in: root) }.value
        let repo = Repo(
            name: (root as NSString).lastPathComponent,
            path: root,
            defaultBranch: try await Git.defaultBranch(of: root),
            accent: Accent.next(usedBy: existingRepos),
            sortOrder: existingRepos.count,
            iconPath: icon?.path,
            iconSource: icon == nil ? .monogram : .detected,
            profileID: profileID
        )
        let added = try await store.upsert(repo)
        await adoptRemoteSuggestions(for: added)
        return added
    }

    @discardableResult
    public func bringProjectBack(_ repoID: RepoID, because reason: String = "a workspace was added to it") async -> Bool {
        let stored = try? await store.repo(id: repoID)
        guard ProjectVisibility.comesBack(stored), let stored else { return false }
        guard (try? await store.update(repoID: repoID) { $0.hidden = false }) != nil else {
            return false
        }
        Self.log.info("showing \(stored.name, privacy: .public) again: \(reason, privacy: .public)")
        return true
    }

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.akira.unifieddev",
        category: "workspace"
    )

    @discardableResult
    func createWorkspace(
        id: WorkspaceID = .new(),
        repo: Repo,
        prompt: String,
        name: String? = nil,
        branch: String? = nil,
        baseBranch: String? = nil,
        origin: WorkspaceOrigin = .user,
        checkout: WorkspaceCheckout? = nil,
        setupPolicy: WorkspaceSetupPolicy = .deferred,
        acceptsStaleBase: Bool = true
    ) async throws -> Workspace {
        let repositoryKey = Git.repositoryPaths(in: repo.path)?.commonDirectory
            ?? URL(fileURLWithPath: repo.path).resolvingSymlinksInPath().standardized.path
        return try await WorktreeCutQueue.shared.cut(in: repositoryKey) {
            if let checkout {
                return try await open(
                    checkout, id: id, repo: repo, name: name, origin: origin, setupPolicy: setupPolicy
                )
            }
            return try await cut(
                id: id, repo: repo, prompt: prompt, name: name, branch: branch,
                baseBranch: baseBranch, origin: origin, setupPolicy: setupPolicy,
                acceptsStaleBase: acceptsStaleBase
            )
        }
    }

    private func cut(
        id: WorkspaceID,
        repo: Repo,
        prompt: String,
        name: String?,
        branch: String?,
        baseBranch: String?,
        origin: WorkspaceOrigin,
        setupPolicy: WorkspaceSetupPolicy,
        acceptsStaleBase: Bool
    ) async throws -> Workspace {
        let settings = SettingsLoader.load(repo: repo.path)
        let base = baseBranch ?? repo.defaultBranch
        let existingBranches = Set(try await Git.branches(of: repo.path))
        let namesABranch = GitRepositoryContext.namesABranch(
            base,
            localBranches: existingBranches,
            remoteReferences: (try? await Git.remoteBranches(of: repo.path)) ?? [],
            remoteNames: (try? await Git.remoteNames(of: repo.path)) ?? []
        )
        let repository = try await Git.repositoryContext(
            in: repo.path, baseBranch: base, baseIsBranchName: namesABranch
        )
        let stem = Git.branchStem(prompt: prompt, prefix: settings.branchPrefix, branch: branch)
        let finalBranch = Git.uniqueBranch(stem, taken: existingBranches)

        let profileFolder = try await profileFolder(of: repo)
        let worktreePath = WorktreePath.free(
            preferred: WorktreePath.preferred(
                branch: finalBranch, project: repo.name, profileFolder: profileFolder, under: workspacesRoot
            )
        ) { FileManager.default.fileExists(atPath: $0) }

        try await Git.addWorktree(
            repo: repo.path,
            path: worktreePath,
            branch: finalBranch,
            base: try await Self.startPoint(of: base, in: repo.path, acceptsStaleBase: acceptsStaleBase),
            branchIsNew: true
        )
        try await Git.recordBase(repository, for: finalBranch, in: worktreePath)

        try copyFiles(settings.filesToCopy, from: repo.path, to: worktreePath)

        let workspace = Workspace(
            id: id,
            repoID: repo.id,
            name: WorkspaceStartPlan.name(supplied: name, checkout: nil, prompt: prompt),
            branch: finalBranch,
            path: worktreePath,
            baseBranch: base,
            setupState: setupPolicy.initialState(script: settings.setupScript, hasSubmodules: Git.hasSubmodules(in: worktreePath)),
            sortOrder: try await store.nextWorkspaceSortOrder(repoID: repo.id),
            origin: origin
        )
        return try await store.upsert(workspace)
    }

    private func open(
        _ checkout: WorkspaceCheckout,
        id: WorkspaceID,
        repo: Repo,
        name: String?,
        origin: WorkspaceOrigin,
        setupPolicy: WorkspaceSetupPolicy
    ) async throws -> Workspace {
        let settings = SettingsLoader.load(repo: repo.path)
        let existingBranches = Set(try await Git.branches(of: repo.path))
        let branch = WorkspaceCheckoutPlan.localBranch(for: checkout, taken: existingBranches)

        let holders = BranchHolder.byBranch(
            worktrees: (try? await Git.worktrees(of: repo.path)) ?? [],
            projectPath: repo.path,
            workspaceNames: BranchHolder.names(
                of: (try? await store.workspaces(repoID: repo.id)) ?? [], in: repo.id
            )
        )
        if let holder = holders[branch] {
            throw BranchInUse(branch: branch, holder: holder)
        }

        let profileFolder = try await profileFolder(of: repo)
        let worktreePath = WorktreePath.free(
            preferred: WorktreePath.preferred(
                branch: branch, project: repo.name, profileFolder: profileFolder, under: workspacesRoot
            )
        ) { FileManager.default.fileExists(atPath: $0) }

        switch checkout {
        case .pullRequest(let request):
            try await Git.addDetachedWorktree(repo: repo.path, path: worktreePath)
            do {
                try await GitHub.$login.withValue(store.gitHubLogin(for: repo.profileID)) {
                    try await ForgePullRequests.checkout(
                        request, repoPath: repo.path, into: worktreePath, localBranch: branch
                    )
                }
            } catch {
                await discardFreshWorktree(of: repo, at: worktreePath)
                throw error
            }
        case .branch(let existing):
            if await Git.branchExists(branch, in: repo.path) {
                try await Git.addWorktree(
                    repo: repo.path, path: worktreePath, branch: branch, base: branch
                )
            } else {
                try await Git.addTrackingWorktree(
                    repo: repo.path, path: worktreePath, branch: branch, remote: existing.remoteName
                )
            }
        }

        try copyFiles(settings.filesToCopy, from: repo.path, to: worktreePath)

        let workspace = Workspace(
            id: id,
            repoID: repo.id,
            name: WorkspaceStartPlan.name(supplied: name, checkout: checkout, prompt: ""),
            branch: branch,
            path: worktreePath,
            baseBranch: checkout.baseBranch(default: repo.defaultBranch),
            setupState: setupPolicy.initialState(script: settings.setupScript, hasSubmodules: Git.hasSubmodules(in: worktreePath)),
            sortOrder: try await store.nextWorkspaceSortOrder(repoID: repo.id),
            origin: origin,
            pullRequestNumber: checkout.pullRequestNumber
        )
        return try await store.upsert(workspace)
    }

    func copyFiles(_ patterns: [String], from source: String, to destination: String) throws {
        let manager = FileManager.default
        let plan = FilesToCopyResolver.resolve(patterns: patterns, in: source, limit: .max)
        for match in plan.matches where !match.isDirectory {
            guard let from = ContainedPath.relative(match.path, inside: source),
                  let to = ContainedPath.relative(match.path, inside: destination, forWriting: true)
            else { continue }
            if manager.fileExists(atPath: to.path) { continue }
            try manager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: from, to: to)
        }
    }

    public static let environmentPrefix = "UD"

    public static let deprecatedEnvironmentPrefix = "CONDUCTOR"

    public static let environmentPrefixes = [environmentPrefix, deprecatedEnvironmentPrefix]

    static func projectName(for repo: Repo) -> String {
        let folder = URL(fileURLWithPath: repo.path).lastPathComponent
        let source = (folder.isEmpty || folder == "/") ? repo.name : folder
        let cleaned = String(source.map { character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "_"
        })
        return cleaned.isEmpty ? "project" : cleaned
    }

    public func environment(for workspace: Workspace, repo: Repo, port: Int) -> [String: String] {
        WorktreeScratch.shield(WorktreeScratch.generated, in: workspace.path)

        let pairs: [(String, String)] = [
            ("IS_LOCAL", "1"),
            ("WORKSPACE_NAME", workspace.branch.replacingOccurrences(of: "/", with: "-")),
            ("WORKSPACE_ID", workspace.id.rawValue),
            ("WORKSPACE_PATH", workspace.path),
            ("PROJECT_NAME", Self.projectName(for: repo)),
            ("ROOT_PATH", repo.path),
            ("DEFAULT_BRANCH", repo.defaultBranch),
            ("PORT", String(port)),
            ("URL_FILE", WorkspaceBrowserURL.path(inWorktree: workspace.path)),
        ]

        var env: [String: String] = [:]
        for (key, value) in pairs {
            for prefix in Self.environmentPrefixes {
                env["\(prefix)_\(key)"] = value
            }
        }
        return env.merging(store.gitHubLogin(for: repo.profileID).everyVariable) { _, login in login }
    }

    public static let setupStoppedNote = "[unifieddev] Setup was stopped before it finished. "
        + "Run setup again to finish it."

    static let setupStopGrace: DispatchTimeInterval = .seconds(5)

    @discardableResult
    public func runSetup(
        workspace: Workspace,
        repo: Repo,
        port: Int,
        operationLease: WorkspaceOperationLease? = nil,
        onExit: (@Sendable (Int) -> Void)? = nil,
        onOutput: @escaping @Sendable (String) -> Void
    ) async -> Bool {
        guard let lease = operationLease ?? WorkspaceOperationLease.acquire(in: workspace.path, operation: .setup),
              lease.isValid(in: workspace.path, operation: .setup) else {
            onOutput("Setup cannot run while another setup or rewind is using this worktree.")
            return false
        }
        defer { if operationLease == nil { lease.release() } }
        do {
            try Task.checkCancellation()
            guard try await store.pendingCheckpointRewind(workspaceID: workspace.id) == nil else {
                onOutput("Resolve the interrupted rewind before running setup. Nothing was started.")
                return false
            }
        } catch {
            onOutput("Unified Dev could not check this workspace's rewind state. Nothing was started.")
            return false
        }
        let settings = SettingsLoader.load(repo: repo.path)
        let launch = ScriptLaunch.resolve(
            text: settings.setupScript, file: settings.scriptFiles[.setup], repo: repo.path
        )

        let hasSubmodules = Git.hasSubmodules(in: workspace.path)
        var preparationLog = ""
        if hasSubmodules {
            _ = try? await store.update(workspaceID: workspace.id) { $0.apply(.runStarted) }
            preparationLog = "Preparing this worktree's submodules.\n"
            onOutput(preparationLog.trimmingCharacters(in: .newlines))
            do {
                guard try await store.pendingCheckpointRewind(workspaceID: workspace.id) == nil else {
                    throw WorkspaceError.recoveryPending
                }
                let output = try await Git.initialiseSubmodules(in: workspace.path)
                preparationLog += output
                if !output.isEmpty { onOutput(output) }
            } catch {
                let note = "Submodule setup failed. Some files may be missing. Run setup again to retry.\n"
                    + error.readableMessage
                onOutput(note)
                let log = preparationLog + note
                _ = try? await store.update(workspaceID: workspace.id) {
                    $0.apply(.runFinished(succeeded: false, log: log))
                }
                onExit?(1)
                return false
            }
        }

        guard let launch else {
            let log = preparationLog
            _ = try? await store.update(workspaceID: workspace.id) {
                $0.apply(hasSubmodules ? .runFinished(succeeded: true, log: log) : .runSkipped(note: nil))
            }
            if hasSubmodules { onExit?(0) }
            return true
        }

        switch launch {
        case .missing(let path):
            let note = "The settings file names \(path) as the setup script and there is nothing "
                + "there, so nothing ran."
            onOutput(note)
            let log = preparationLog + note
            _ = try? await store.update(workspaceID: workspace.id) {
                $0.apply(hasSubmodules ? .runFinished(succeeded: true, log: log) : .runSkipped(note: note))
            }
            return true
        case .executable, .source:
            break
        }

        await LoginShellPath.ready()

        _ = try? await store.update(workspaceID: workspace.id) { $0.apply(.runStarted) }

        let env = environment(for: workspace, repo: repo, port: port)
        let runner = StreamingProcess(
            executable: launch.executable,
            arguments: launch.arguments,
            cwd: workspace.path,
            environment: Shell.environment(extra: env)
        )

        var log = preparationLog
        var didStart = false
        await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                guard try await store.pendingCheckpointRewind(workspaceID: workspace.id) == nil else {
                    throw WorkspaceError.recoveryPending
                }
                let lines = runner.lines
                didStart = true
                try Task.checkCancellation()
                for try await line in lines {
                    try Task.checkCancellation()
                    log += line + "\n"
                    onOutput(line)
                }
            } catch {
                if Task.isCancelled { runner.terminate() }
                log += "\n\(error)\n"
                onOutput("\(error)")
            }
        } onCancel: {
            runner.terminate()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.setupStopGrace) {
                runner.kill()
            }
        }

        if Task.isCancelled {
            log += Self.setupStoppedNote + "\n"
            onOutput(Self.setupStoppedNote)
        }

        let status: Int32? = didStart ? await runner.exitStatus : nil
        if let status { onExit?(Int(status)) }
        let succeeded = status == 0 && !Task.isCancelled
        let printed = log
        _ = try? await store.update(workspaceID: workspace.id) {
            $0.apply(.runFinished(succeeded: succeeded, log: printed))
        }
        return succeeded
    }

    public func safetyReport(
        workspace: Workspace, repo: Repo, mergedPullRequestHead: String? = nil
    ) async throws -> WorkspaceSafetyReport {
        if await preservesFolderWhenArchiving(workspace) {
            var report = WorkspaceSafetyReport()
            report.preservedFolderPath = workspace.path
            return report
        }
        return try await Git.safetyReport(
            worktree: workspace.path,
            branch: workspace.branch,
            base: workspace.baseBranch,
            repo: repo.path,
            mergedPullRequestHead: mergedPullRequestHead
        )
    }

    private func preservesFolderWhenArchiving(_ workspace: Workspace) async -> Bool {
        guard FileManager.default.fileExists(atPath: workspace.path) else { return false }
        return !(await Git.isRepository(workspace.path))
    }

    @discardableResult
    public func ensurePort(for workspace: Workspace) async -> Int {
        let current = (try? await store.workspace(id: workspace.id))?.port ?? workspace.port
        if current != 0 { return current }

        let taken = await takenPorts(excluding: workspace.id)
        let allocated = await Task.detached { (try? PortAllocator.allocate(taken: taken)) ?? 0 }.value
        guard allocated != 0 else { return 0 }

        let written = try? await store.update(workspaceID: workspace.id) { row in
            if row.port == 0 { row.port = allocated }
        }
        return written?.port ?? allocated
    }

    func takenPorts(excluding id: WorkspaceID) async -> Set<Int> {
        let rows = (try? await store.workspaces()) ?? []
        var taken: Set<Int> = []
        for row in rows where row.id != id && row.port != 0 {
            taken.formUnion(row.port..<(row.port + PortAllocator.blockSize))
        }
        return taken
    }

    public static let archiveScriptTimeout: Duration = .seconds(600)

    @discardableResult
    public func archive(
        workspace: Workspace,
        repo: Repo,
        deleteBranch: Bool? = nil,
        force: Bool = false,
        mergedPullRequestHead: String? = nil,
        measuredTip: String? = nil,
        archiveScriptTimeout: Duration = WorkspaceManager.archiveScriptTimeout
    ) async throws -> ArchiveKeptBranch? {
        guard workspace.state == .active else { return nil }
        try await refuseArchivingAnOrchestrator(workspace.id)
        try await store.requireWorkspaceCanBeRemoved(id: workspace.id)

        let worktreeWasOnDisk = FileManager.default.fileExists(atPath: workspace.path)

        let settings = SettingsLoader.load(repo: repo.path)
        let shouldDeleteBranch = ArchiveBranchDeletion.applies(
            requested: deleteBranch, settings: settings,
            workspace: workspace, defaultBranch: repo.defaultBranch
        )

        let isPullRequestMerged = mergedPullRequestHead != nil
        let tipAtStart = if let measuredTip { measuredTip } else {
            await Git.revision(of: "refs/heads/\(workspace.branch)", in: repo.path)
        }
        let report: WorkspaceSafetyReport?
        if force {
            report = try? await safetyReport(
                workspace: workspace, repo: repo, mergedPullRequestHead: mergedPullRequestHead
            )
        } else {
            let computed = try await safetyReport(
                workspace: workspace, repo: repo, mergedPullRequestHead: mergedPullRequestHead
            )
            guard computed.isSafeToDiscard(
                deletingBranch: shouldDeleteBranch, isPullRequestMerged: isPullRequestMerged
            ) else {
                throw WorkspaceError.unsafeToArchive(computed)
            }
            report = computed
        }

        if report?.preservedFolderPath != nil {
            try await store.update(workspaceID: workspace.id) { $0.archive() }
            try await store.recordPullRequestSeenOpen(nil, workspaceID: workspace.id)
            return nil
        }

        let archiveLaunch = ScriptLaunch.resolve(
            text: settings.archiveScript, file: settings.scriptFiles[.archive], repo: repo.path
        )
        let archiveRuns: Bool
        switch archiveLaunch {
        case .executable, .source: archiveRuns = true
        case .missing, nil: archiveRuns = false
        }
        if let archiveLaunch, archiveRuns,
           FileManager.default.fileExists(atPath: workspace.path) {
            await LoginShellPath.ready()
            let stored = try? await store.workspace(id: workspace.id)
            let env = environment(for: workspace, repo: repo, port: stored?.port ?? workspace.port)
            let result: ShellResult
            do {
                result = try await Shell.run(
                    archiveLaunch.executable, archiveLaunch.arguments,
                    cwd: workspace.path, env: env, timeout: archiveScriptTimeout
                )
            } catch let failure as ShellFailure {
                throw WorkspaceError.archiveScriptIncomplete(failure)
            }
            guard result.ok else {
                throw WorkspaceError.archiveScriptFailed(
                    status: result.status,
                    output: result.stderr.isEmpty ? result.stdout : result.stderr
                )
            }
        }

        try await refuseArchivingAnOrchestrator(workspace.id)
        try await store.requireWorkspaceCanBeRemoved(id: workspace.id)
        if FileManager.default.fileExists(atPath: workspace.path) {
            let plansAreSafe = try await AgentPlans.keep(
                worktree: workspace.path, repo: repo.path, acceptingLoss: force
            )
            guard plansAreSafe else {
                throw WorkspaceError.unsafeToArchive(try await safetyReport(
                    workspace: workspace, repo: repo, mergedPullRequestHead: mergedPullRequestHead
                ))
            }
        }
        try await removeWorktree(of: repo, at: workspace.path, force: force)

        let keptBranch: ArchiveKeptBranch?
        if shouldDeleteBranch {
            keptBranch = await deleteBranchAfterArchiving(
                workspace: workspace,
                repo: repo,
                worktreeWasOnDisk: worktreeWasOnDisk,
                force: force,
                report: report,
                tipAtStart: tipAtStart,
                mergedPullRequestHead: mergedPullRequestHead
            )
        } else {
            keptBranch = nil
        }

        try await store.update(workspaceID: workspace.id) { $0.archive() }
        try await store.recordPullRequestSeenOpen(nil, workspaceID: workspace.id)
        return keptBranch
    }

    private func deleteBranchAfterArchiving(
        workspace: Workspace,
        repo: Repo,
        worktreeWasOnDisk: Bool,
        force: Bool,
        report: WorkspaceSafetyReport?,
        tipAtStart: String?,
        mergedPullRequestHead: String?
    ) async -> ArchiveKeptBranch? {
        let branch = workspace.branch
        var lostNow: Int?
        if worktreeWasOnDisk {
            if (try? await Git.deleteBranch(branch, in: repo.path)) != nil { return nil }
            let isPullRequestMerged = mergedPullRequestHead != nil
            let measured = try? await Git.safetyReport(
                worktree: workspace.path,
                branch: branch,
                base: workspace.baseBranch,
                repo: repo.path,
                mergedPullRequestHead: mergedPullRequestHead
            )
            lostNow = measured?.commitsLostWithBranch(deletingBranch: true, isPullRequestMerged: isPullRequestMerged)
            let currentTip = await Git.revision(of: "refs/heads/\(branch)", in: repo.path)
            let acceptedLoss = ArchiveBranchDeletion.acceptedLoss(
                force: force,
                tipUnchanged: tipAtStart != nil && currentTip == tipAtStart,
                lostAtStart: report?.commitsLostWithBranch(
                    deletingBranch: true, isPullRequestMerged: isPullRequestMerged
                )
            )
            if ArchiveBranchDeletion.forcesDeletion(lostNow: lostNow, acceptedLoss: acceptedLoss) {
                try? await Git.deleteBranch(branch, in: repo.path, force: true)
                lostNow = nil
            }
        }
        guard await Git.branchExists(branch, in: repo.path) else { return nil }
        return ArchiveKeptBranch(branch: branch, commitsNowhereElse: lostNow)
    }

    private func refuseArchivingAnOrchestrator(_ id: WorkspaceID) async throws {
        guard let stored = try await store.workspace(id: id) else { return }
        let active = try await store.workspaces(repoID: stored.repoID)
        let objection = OrchestratorRole.archiveObjection(to: stored)
            ?? OrchestratorRole.removalObjection(toWorktreeAt: stored.path, among: active)
        guard let objection else { return }
        throw WorkspaceError.orchestratorRefused(objection)
    }

    @discardableResult
    public func refreshDiffStat(workspace: Workspace) async -> Bool {
        await refreshBranch(workspace: workspace)
        guard let stat = try? await Git.diffStat(worktree: workspace.path, base: workspace.baseBranch) else {
            return false
        }
        do {
            try Task.checkCancellation()
            try await store.updateDiffStat(
                workspaceID: workspace.id,
                additions: stat.additions,
                deletions: stat.deletions,
                files: stat.files
            )
            return true
        } catch { return false }
    }
}

public extension Workspace {
    func with(_ change: (inout Workspace) -> Void) -> Workspace {
        var copy = self
        change(&copy)
        return copy
    }
}

public extension Session {
    func with(_ change: (inout Session) -> Void) -> Session {
        var copy = self
        change(&copy)
        return copy
    }
}

public extension Repo {
    func with(_ change: (inout Repo) -> Void) -> Repo {
        var copy = self
        change(&copy)
        return copy
    }
}

public enum PortAllocatorError: Error, CustomStringConvertible {
    case exhausted(start: Int, limit: Int)

    public var description: String {
        switch self {
        case .exhausted(let start, let limit):
            "no free block of ten ports between \(start) and \(limit)"
        }
    }
}

public enum PortAllocator {
    public static let blockSize = 10

    public static func allocate(taken: Set<Int>, start: Int = 3_100, limit: Int = 65_000) throws -> Int {
        var port = start
        while port + blockSize - 1 <= limit {
            if isBlockAvailable(from: port, taken: taken) { return port }
            port += blockSize
        }
        throw PortAllocatorError.exhausted(start: start, limit: limit)
    }

    static func isBlockAvailable(from start: Int, taken: Set<Int>) -> Bool {
        for port in start..<(start + blockSize) {
            if taken.contains(port) || !isFree(port) { return false }
        }
        return true
    }

    static func isFree(_ port: Int) -> Bool {
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        guard handle >= 0 else { return true }
        defer { close(handle) }

        var reuse: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = INADDR_ANY

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bound == 0
    }
}

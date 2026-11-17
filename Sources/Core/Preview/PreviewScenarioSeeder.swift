import Foundation

public struct PreviewScenarioSeeder: Sendable {
    public struct Outcome: Sendable, Equatable {
        public var projects: Int
        public var workspaces: Int
        public var chats: Int
        public var quotas: Int
        public var archived = 0
        public var suggestions = 0
        public var recentFolders = 0
        public var browserTabs: [BrowserTab] = []
        public var transcripts = 0
        public var accounts = 0
        public var notifications = 0
    }

    public struct BrowserTab: Sendable, Equatable {
        public var workspaceID: WorkspaceID
        public var address: String
    }

    static let author = [
        "-c", "user.name=Preview Scenario",
        "-c", "user.email=preview@unifieddev.invalid",
        "-c", "commit.gpgsign=false",
        "-c", "tag.gpgsign=false",
        "-c", "core.hooksPath=/dev/null",
        "-c", "core.fsmonitor=false",
        "-c", "init.templateDir=",
    ]

    public let manager: WorkspaceManager
    public let scratchRoot: String

    public init(manager: WorkspaceManager, scratchRoot: String) {
        self.manager = manager
        self.scratchRoot = scratchRoot
    }

    public var projectsRoot: String { scratchRoot + "/projects" }
    public var remotesRoot: String { scratchRoot + "/remotes" }

    public func seed(_ scenario: PreviewScenario, at now: Date = Date()) async throws -> Outcome {
        let problems = scenario.problems
        guard problems.isEmpty else { throw PreviewScenarioError.invalid(problems) }
        let existing = try await manager.store.repos()
        guard existing.isEmpty else { throw PreviewScenarioError.alreadySeeded(projects: existing.map(\.name).sorted()) }
        try await makeLooseFolders(scenario)

        var outcome = Outcome(projects: 0, workspaces: 0, chats: 0, quotas: 0)
        let profileIDs = try await seedProfiles(scenario)
        try await seedAccountRows(scenario, profiles: profileIDs, home: TranscriptHome.seedable())
        var repos: [String: RepoID] = [:]
        for project in scenario.projects {
            let path = try await makeRepository(project)
            try await publishBranches(project, at: path)
            let repo = try await manager.addRepository(at: path, profileID: profileIDs[project.profile?.lowercased() ?? Self.initialKey] ?? .initial)
            outcome.projects += 1
            repos[project.name] = repo.id
            var started: [String: WorkspaceID] = [:]
            for workspace in project.workspaces {
                let (workspaceID, chats) = try await start(
                    workspace, in: repo, among: started, accounts: scenario.accounts, at: now
                )
                started[workspace.name] = workspaceID
                outcome.workspaces += 1
                outcome.chats += chats
                if workspace.state.isArchived { outcome.archived += 1 }
                if let browser = workspace.browser {
                    outcome.browserTabs.append(BrowserTab(workspaceID: workspaceID, address: browser))
                }
            }
            if project.hidden { _ = try await manager.store.update(repoID: repo.id) { $0.hidden = true } }
            try await publishRemoteAhead(project)
            try await slowDownRemote(project, at: path)
        }
        if let active = scenario.activeProfile, let id = profileIDs[active.lowercased()] {
            try await manager.store.setActiveProfile(id)
        }
        outcome.transcripts = try seedTranscripts(scenario, at: now, home: TranscriptHome.seedable())
        outcome.accounts = try seedAgentAccounts(scenario, home: TranscriptHome.seedable(), at: now)
        try await seedAccountChoices(
            scenario, repos: repos, profiles: profileIDs, home: TranscriptHome.seedable()
        )
        outcome.suggestions = try await seedSuggestions(scenario)
        outcome.recentFolders = try await seedRecentFolders(scenario)
        outcome.notifications = try await seedNotifications(scenario, at: now)
        if !scenario.quotas.isEmpty {
            try await manager.store.recordQuotas(scenario.quotas.map { $0.quota(at: now) })
            outcome.quotas = scenario.quotas.count
        }
        return outcome
    }

    func makeRepository(_ project: PreviewScenario.Project) async throws -> String {
        let path = projectsRoot + "/" + project.name
        let remote = remotesRoot + "/" + project.name + ".git"
        guard !FileManager.default.fileExists(atPath: path),
              !FileManager.default.fileExists(atPath: remote) else {
            throw WorkspaceError.pathInUse(FileManager.default.fileExists(atPath: path) ? path : remote)
        }
        try FileManager.default.createDirectory(atPath: projectsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: remotesRoot, withIntermediateDirectories: true)

        if project.remote.exists {
            try await git(["init", "-q", "--bare", "--initial-branch=main", "--", remote], in: remotesRoot)
            try await git(["clone", "-q", "--", remote, path], in: projectsRoot)
        } else {
            try await git(["init", "-q", "--initial-branch=main", "--", project.name], in: projectsRoot)
        }

        try Self.write(project.files, into: path)
        let history = project.commits.isEmpty ? ["Start \(project.name)"] : project.commits
        for (index, message) in history.enumerated() {
            try await commit(message, in: path, adding: index == 0 ? "# \(project.name)\n" : nil)
        }
        guard project.remote.exists else { return path }
        try await git(["push", "-q", "-u", "origin", "main"], in: path)
        try await git(["remote", "set-head", "origin", "main"], in: path)
        return path
    }

    func publishRemoteAhead(_ project: PreviewScenario.Project) async throws {
        guard !project.remoteAhead.isEmpty else { return }
        let remote = remotesRoot + "/" + project.name + ".git"
        let upstream = remotesRoot + "/" + project.name + ".upstream"
        try await git(["clone", "-q", remote, upstream], in: remotesRoot)
        for message in project.remoteAhead {
            try await commit(message, in: upstream, adding: nil)
        }
        try await git(["push", "-q", "origin", "main"], in: upstream)
        try FileManager.default.removeItem(atPath: upstream)
    }

    func slowDownRemote(_ project: PreviewScenario.Project, at path: String) async throws {
        guard let uploadPack = project.remote.uploadPack else { return }
        try await git(["config", "remote.origin.uploadpack", uploadPack], in: path)
    }

    func publishBranches(_ project: PreviewScenario.Project, at path: String) async throws {
        guard !project.branches.isEmpty else { return }
        for branch in project.branches {
            try await git(["checkout", "-q", "-b", branch, "main"], in: path)
            try await commit("Start \(branch)", in: path, adding: nil)
            guard project.remote.exists else { continue }
            try await git(["push", "-q", "-u", "origin", branch], in: path)
        }
        try await git(["checkout", "-q", "main"], in: path)
    }

    func start(
        _ workspace: PreviewScenario.Workspace, in repo: Repo, among earlier: [String: WorkspaceID] = [:],
        accounts: [PreviewScenario.Account] = [], at now: Date
    ) async throws -> (WorkspaceID, Int) {
        let started = try await manager.start(WorkspaceStartRequest(
            repo: repo,
            prompt: workspace.name,
            origin: Self.origin(of: workspace, among: earlier),
            branch: workspace.branch,
            name: workspace.name,
            opensSession: workspace.chats.isEmpty,
            setupPolicy: .skip,
            announcesToOrchestrator: false
        ))
        for message in workspace.commits {
            try await commit(message, in: started.workspace.path, adding: nil)
        }
        try Self.apply(workspace.changes, to: started.workspace.path)
        try Self.scatter(workspace.spareFiles, into: started.workspace.path)
        for (order, chat) in workspace.chats.enumerated() {
            let session = try await manager.store.upsert(Self.session(of: chat, in: started.workspace.id, at: order))
            try await manager.store.setSetting(ComposerControls.defaultsAppliedKey(sessionID: session.id), "1")
            for (place, line) in chat.messages.enumerated() {
                if let question = line.question {
                    try await ask(question, at: place, in: session)
                    continue
                }
                if let handoff = line.handoff {
                    try await manager.store.switchSegment(
                        sessionID: session.id, to: Self.target(of: handoff, among: accounts)
                    )
                    continue
                }
                _ = try await manager.store.appendNext(
                    sessionID: session.id,
                    kind: Self.kind(of: line.from),
                    payload: try Self.payload(line.text, from: line.from)
                )
            }
        }
        try await seedRecord(of: workspace.recordMegabytes, in: started.workspace.id)
        try await manager.store.touch(
            workspaceID: started.workspace.id,
            unread: workspace.unread ? true : nil,
            at: workspace.lastActiveMoment(from: now) ?? now
        )
        if workspace.pinned {
            _ = try await manager.store.update(workspaceID: started.workspace.id) { $0.pinned = true }
        }
        if workspace.orchestrator {
            _ = try await manager.store.setOrchestrator(true, workspaceID: started.workspace.id)
        }
        if workspace.state.isArchived {
            try await manager.archive(
                workspace: started.workspace,
                repo: repo,
                deleteBranch: !workspace.state.keepsItsBranch,
                force: true
            )
            if let moment = workspace.archivedMoment(from: now) {
                _ = try await manager.store.update(workspaceID: started.workspace.id) { $0.archivedAt = moment }
            }
        }
        return (started.workspace.id, workspace.chats.count)
    }

    private func seedRecord(of megabytes: Int, in workspaceID: WorkspaceID) async throws {
        guard megabytes > 0 else { return }
        let session = try await manager.store.upsert(Session(workspaceID: workspaceID, title: "Long transcript"))
        let line = String(repeating: "x", count: 1_000_000)
        for _ in 0..<megabytes {
            _ = try await manager.store.appendNext(
                sessionID: session.id,
                kind: .assistantText,
                payload: try Self.payload(line, from: .agent)
            )
        }
    }

    private func ask(
        _ question: PreviewScenario.Question, at place: Int, in session: Session
    ) async throws {
        let requestID = "preview-\(session.id.rawValue)-q\(place)"
        guard let payload = question.payload(
            requestID: requestID, toolUseID: "toolu_\(requestID)"
        ), let ask = PermissionAsk.decode(payload: payload) else {
            throw PreviewScenarioError.invalid(["a question could not be written as one"])
        }

        _ = try await manager.store.appendNext(
            sessionID: session.id, kind: .permissionAsk, payload: payload
        )
        try await manager.store.appendPermissionAsk(sessionID: session.id, ask: ask)

        guard question.isAnswered else { return }

        try await manager.store.resolvePermissionAsk(
            id: requestID,
            decision: PermissionDecision.answeredName,
            answers: question.answers
        )
    }

    static func origin(
        of workspace: PreviewScenario.Workspace, among earlier: [String: WorkspaceID]
    ) -> WorkspaceOrigin {
        guard let starter = workspace.startedBy, let parent = earlier[starter] else { return .user }
        return .agent(parentWorkspaceID: parent, spawnToolUseID: "toolu_preview_\(workspace.branch)")
    }

    static func write(_ files: [String: String], into path: String) throws {
        for (file, contents) in files.sorted(by: { $0.key < $1.key }) {
            let target = path + "/" + file
            try FileManager.default.createDirectory(
                atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true
            )
            try contents.write(toFile: target, atomically: true, encoding: .utf8)
        }
    }

    static func apply(_ changes: [String: String?], to path: String) throws {
        let deleted = changes.filter { $0.value?.isEmpty ?? true }.keys.sorted()
        for file in deleted {
            try FileManager.default.removeItem(atPath: path + "/" + file)
        }
        try write(changes.compactMapValues { $0?.isEmpty == false ? $0 : nil }, into: path)
    }

    static func scatter(_ count: Int, into path: String) throws {
        guard count > 0 else { return }
        let names = PreviewScenario.Workspace.spareFileNames(count)
        try write(Dictionary(uniqueKeysWithValues: names.map { ($0, "Something nobody committed.\n") }), into: path)
    }

    static func kind(of speaker: PreviewScenario.Line.Speaker) -> MessageKind {
        switch speaker {
        case .user: .user
        case .agent: .assistantText
        case .app: .crew
        }
    }

    static func session(of chat: PreviewScenario.Chat, in workspaceID: WorkspaceID, at order: Int) -> Session {
        var session = Session(workspaceID: workspaceID, title: chat.title, sortOrder: order)
        if let agent = chat.agent { session.agentKind = agent }
        if let model = chat.model { session.model = model }
        return session
    }

    static func payload(_ text: String, from speaker: PreviewScenario.Line.Speaker) throws -> Data {
        if speaker == .app { return try CrewMessage.appRequest(text).payload() }
        let role = speaker == .user ? "user" : "assistant"
        let message: [String: Any] = [
            "type": role,
            "message": ["role": role, "content": [["type": "text", "text": text]]],
        ]
        return try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
    }

    private func commit(_ message: String, in path: String, adding header: String?) async throws {
        let notes = path + "/NOTES.md"
        let existing = (try? String(contentsOfFile: notes, encoding: .utf8)) ?? (header ?? "")
        try (existing + "- \(message)\n").write(toFile: notes, atomically: true, encoding: .utf8)
        try await git(["add", "-A"], in: path)
        try await git(["commit", "-q", "-m", message], in: path)
    }

    private func git(_ arguments: [String], in directory: String) async throws {
        try await Git.check(Self.author + arguments, in: directory)
    }
}

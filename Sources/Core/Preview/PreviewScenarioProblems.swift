import Foundation

public extension PreviewScenario {
    static let initialProfileName = "Unified"

    private var declaredProfileNames: Set<String> {
        Set(profiles.map { $0.name.lowercased() }).union([Self.initialProfileName.lowercased()])
    }

    private var profileProblems: [String] {
        var problems: [String] = []
        var seen = Set([Self.initialProfileName.lowercased()])
        for profile in profiles where !seen.insert(profile.name.lowercased()).inserted {
            problems.append("profile \"\(profile.name)\" is declared twice, or is the profile Unified already has")
        }
        for profile in profiles where profile.name.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("a profile has no name")
        }
        let declared = declaredProfileNames
        for project in projects {
            if let name = project.profile, !declared.contains(name.lowercased()) {
                problems.append("project \"\(project.name)\" is in profile \"\(name)\", which the scenario does not declare")
            }
        }
        for name in reachableProfiles where !declared.contains(name.lowercased()) {
            problems.append("reachableProfiles names \(name), which is not a profile of this scenario")
        }
        if let name = activeProfile, !declared.contains(name.lowercased()) {
            problems.append("the active profile \"\(name)\" is not declared by the scenario")
        }
        return problems
    }

    var problems: [String] {
        var problems: [String] = []
        if projects.isEmpty { problems.append("the scenario names no projects") }
        problems += profileProblems
        var seen = Set<String>()
        for project in projects {
            let name = project.name
            if !Self.isFolderName(name) {
                problems.append("project \"\(name)\" is not a plain folder name")
            }
            if !seen.insert(name.lowercased()).inserted {
                problems.append("project \"\(name)\" is named twice")
            }
            for path in project.files.keys where !Self.isRelativeFile(path) {
                problems.append("project \"\(name)\" writes \"\(path)\", which is not a path inside the project")
            }
            var branches = Set<String>()
            var startedSoFar: Set<String> = []
            if project.workspaces.filter(\.orchestrator).count > 1 {
                problems.append("project \"\(name)\" seeds more than one orchestrator")
            }
            for workspace in project.workspaces {
                defer { startedSoFar.insert(workspace.name) }
                if startedSoFar.contains(workspace.name) {
                    problems.append("workspace \"\(workspace.name)\" is named twice in \"\(name)\"")
                }
                if let starter = workspace.startedBy, starter == workspace.name {
                    problems.append("workspace \"\(workspace.name)\" in \"\(name)\" is started by itself")
                }
                if let starter = workspace.startedBy, starter != workspace.name,
                   !startedSoFar.contains(starter) {
                    problems.append(
                        "workspace \"\(workspace.name)\" in \"\(name)\" is started by \"\(starter)\", "
                            + "which is not a workspace listed before it in the same project"
                    )
                }
                if workspace.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    problems.append("a workspace in \"\(name)\" has no name")
                }
                if !Git.isValidBranchName(workspace.branch) || workspace.branch == "main" {
                    problems.append("workspace \"\(workspace.name)\" in \"\(name)\" has an unusable branch \"\(workspace.branch)\"")
                }
                if !branches.insert(workspace.branch).inserted {
                    problems.append("branch \"\(workspace.branch)\" is used twice in \"\(name)\"")
                }
                for path in workspace.changes.keys where !Self.isRelativeFile(path) {
                    problems.append("workspace \"\(workspace.name)\" in \"\(name)\" changes \"\(path)\", which is not a path inside the worktree")
                }
                if let browser = workspace.browser, BrowserAddress.url(from: browser) == nil {
                    problems.append("workspace \"\(workspace.name)\" in \"\(name)\" opens \"\(browser)\", which is not an address")
                }
                problems += Self.questionProblems(in: workspace)
                if workspace.orchestrator, workspace.state.isArchived {
                    problems.append(
                        "workspace \"\(workspace.name)\" in \"\(name)\" is seeded archived "
                            + "and as the orchestrator, which is never archived"
                    )
                }
                if let hours = workspace.lastActive, hours < 0 {
                    problems.append(
                        "workspace \"\(workspace.name)\" in \"\(name)\" asks for a lastActive of \(hours) "
                            + "hours ago, and a preview cannot seed work done in the future"
                    )
                }
                if let hours = workspace.archivedAgo, hours < 0 || !workspace.state.isArchived {
                    problems.append(
                        "workspace \"\(workspace.name)\" in \"\(name)\" asks for an archivedAgo of \(hours) "
                            + "hours, and only an archived workspace can have one, never in the future"
                    )
                }
                if !(0...Workspace.recordMegabyteCeiling).contains(workspace.recordMegabytes) {
                    problems.append(
                        "workspace \"\(workspace.name)\" in \"\(name)\" asks for \(workspace.recordMegabytes) "
                            + "recordMegabytes, and the preview seeds between 0 and \(Workspace.recordMegabyteCeiling)"
                    )
                }
                if workspace.state.isArchived, !workspace.changes.isEmpty || workspace.spareFiles > 0 {
                    problems.append(
                        "workspace \"\(workspace.name)\" in \"\(name)\" is seeded archived and also carries "
                            + "work git has never seen, which archiving would throw away"
                    )
                }
                if workspace.state.isArchived, workspace.browser != nil {
                    problems.append(
                        "workspace \"\(workspace.name)\" in \"\(name)\" is seeded archived and also opens a "
                            + "browser tab, and an archived workspace has no worktree to open one in"
                    )
                }
                if !(0...Workspace.spareFileCeiling).contains(workspace.spareFiles) {
                    problems.append(
                        "workspace \"\(workspace.name)\" in \"\(name)\" asks for \(workspace.spareFiles) "
                            + "spareFiles, and the preview seeds between 0 and \(Workspace.spareFileCeiling)"
                    )
                }
            }
            if !project.remote.exists, !project.remoteAhead.isEmpty {
                problems.append(
                    "project \"\(name)\" has no remote, so nothing can be ahead of one"
                )
            }
            for branch in project.branches {
                if !Git.isValidBranchName(branch) || branch == "main" {
                    problems.append("branch \"\(branch)\" in \"\(name)\" is unusable")
                }
                if !branches.insert(branch).inserted {
                    problems.append("branch \"\(branch)\" is used twice in \"\(name)\"")
                }
            }
            for branch in branches.sorted() where branches.contains(where: { branch.hasPrefix($0 + "/") }) {
                problems.append("branch \"\(branch)\" in \"\(name)\" sits under another branch of the scenario, which git cannot hold")
            }
        }
        problems += suggestionProblems
        problems += quotaProblems
        problems += recentProblems
        problems += notificationProblems
        problems += transcriptProblems
        problems += accountProblems
        problems += updateProblems
        problems += agentSettingsProblems
        return problems
    }

    var accountProblems: [String] {
        var found: [String] = []
        var ids = Set<AgentAccountID>()
        for account in accounts {
            found += account.problems
            if !ids.insert(account.id).inserted {
                found.append(account.label == nil
                    ? "\(account.provider.label) is given two default accounts, and it can hold one"
                    : "\(account.provider.label) account \"\(account.label ?? "")\" is declared twice")
            }
        }
        for account in accounts {
            guard let named = account.profile, !declaredProfileNames.contains(named.lowercased()) else { continue }
            found.append("an account names a profile, \(named), that the scenario does not declare")
        }
        for project in projects {
            for (key, label) in project.accounts.sorted(by: { $0.key < $1.key }) {
                guard let provider = AgentKind(rawValue: key) else {
                    found.append("project \"\(project.name)\" chooses an account for \"\(key)\", which is no agent")
                    continue
                }
                if !accounts.contains(where: { $0.provider == provider && $0.label == label }) {
                    found.append(
                        "project \"\(project.name)\" chooses \(provider.label) account \"\(label)\", "
                            + "which the scenario does not declare"
                    )
                }
            }
            for chat in project.workspaces.flatMap(\.chats) {
                for handoff in chat.messages.compactMap(\.handoff) {
                    guard let label = handoff.account,
                          !accounts.contains(where: { $0.provider == handoff.agent && $0.label == label })
                    else { continue }
                    found.append(
                        "\"\(chat.title)\" moves to \(handoff.agent.label) account \"\(label)\", "
                            + "which the scenario does not declare"
                    )
                }
            }
        }
        return found
    }

    var transcriptProblems: [String] {
        var found = transcripts.flatMap(\.problems)
        let names = Set(projects.map(\.name))
        for transcript in transcripts {
            guard let project = transcript.project, !names.contains(project) else { continue }
            found.append("a transcript names project \"\(project)\", which the scenario does not create")
        }
        return found
    }

    internal static func questionProblems(in workspace: Workspace) -> [String] {
        var problems: [String] = []
        for chat in workspace.chats {
            for line in chat.messages {
                guard let question = line.question else { continue }
                if line.from == .user {
                    problems.append("a question in \"\(chat.title)\" is asked by the owner")
                }
                if !line.text.isEmpty {
                    problems.append("a question in \"\(chat.title)\" also carries prose")
                }
                problems += question.problems
            }
            problems += handoffProblems(in: chat)
            for line in chat.messages where line.question == nil && line.handoff == nil && line.text.isEmpty {
                problems.append("a line in \"\(chat.title)\" says nothing and asks nothing")
            }
        }
        return problems
    }

    internal static func handoffProblems(in chat: Chat) -> [String] {
        var problems: [String] = []
        var running = chat.agent ?? .claudeCode
        var runningAccount: String?
        for line in chat.messages {
            guard let handoff = line.handoff else { continue }
            if line.from == .user || !line.text.isEmpty || line.question != nil {
                problems.append("a move to another agent in \"\(chat.title)\" also carries prose or a question")
            }
            if handoff.model.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append("a move to \(handoff.agent.label) in \"\(chat.title)\" names no model")
            }
            if handoff.agent == running, handoff.account == runningAccount {
                problems.append("\"\(chat.title)\" already runs under \(running.label) where it is moved to it")
            }
            running = handoff.agent
            runningAccount = handoff.account
        }
        return problems
    }

    internal static func isFolderName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64, !name.hasPrefix("."), !name.hasPrefix("-") else { return false }
        return name.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_" || $0 == "."
        }
    }

    internal static func isRelativeFile(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && $0.lowercased() != ".git" }
    }
}

import Foundation
import Core

extension AppModel {
    func bridgeToolbox() -> BridgeToolbox {
        let browser: BrowserPaneCommanding = { [weak self] command, workspaceID in
            guard let self else { return .refused("Unified Dev is still starting up.") }
            return await self.driveBrowserForBridge(command, in: workspaceID)
        }
        let terminal: TerminalPaneCommanding = { [weak self] command, workspaceID in
            guard let self else { return .refused("Unified Dev is still starting up.") }
            return await self.driveTerminalForBridge(command, in: workspaceID)
        }

        return BridgeToolbox(handlers: BridgeToolbox.standard.handlers + [
            WorkspaceStartTool { [weak self] order, project, identity, origin in
                guard let self else { throw AppNotReady.stillStartingUp }
                return try await self.startWorkspaceForBridge(
                    order, in: project, from: identity, origin: origin
                )
            },
            PaneOpenTool { [weak self] order, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.openPaneForBridge(order, in: workspaceID)
            },
            TerminalStartTool { [weak self] order, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.startTerminalForBridge(order, in: workspaceID)
            },
            TerminalReadTool(terminal),
            TerminalWriteTool(terminal),
            TerminalSendKeyTool(terminal),
            MediaShowTool { [weak self] order, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return self.showMediaForBridge(order, in: workspaceID)
            },
            CanvasShowTool { [weak self] order, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.showCanvasForBridge(order, in: workspaceID)
            },
            CanvasReadTool { [weak self] path, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.readCanvasForBridge(path, in: workspaceID)
            },
            CanvasEditTool { [weak self] path, operations, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.editCanvasForBridge(path, operations: operations, in: workspaceID)
            },
            CanvasCommentResolveTool { [weak self] order, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.resolveCanvasCommentForBridge(order, in: workspaceID)
            },
            CanvasRenderTool { [weak self] path, frame, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.renderCanvasForBridge(path, frame: frame, in: workspaceID)
            },
            PaneSplitTool { [weak self] order, axis, anchor, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.splitPaneForBridge(order, axis: axis, anchor: anchor, in: workspaceID)
            },
            PaneCloseTool { [weak self] kind, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.closePaneForBridge(kind, in: workspaceID)
            },
            PaneRenameTool { [weak self] title, kind, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.renamePaneForBridge(title, kind: kind, in: workspaceID)
            },
            PaneListTool { [weak self] workspaceID in
                guard let self else { return nil }
                return await self.paneCensusForBridge(workspaceID)
            },
            WorkspaceTabsTool { [weak self] workspaceID in
                guard let self else { return nil }
                return await self.workspaceTabsForBridge(workspaceID)
            },
            WorkspaceTabSelectTool { [weak self] choice, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.selectWorkspaceTabForBridge(choice, in: workspaceID)
            },
            BrowserReadTool(browser),
            BrowserReloadTool(browser),
            BrowserGoTool(browser),
            BrowserScrollTool(browser),
            BrowserScreenshotTool(browser),
            BrowserTextTool(browser),
            BrowserPageOutlineTool(browser),
            BrowserClickTool(browser),
            BrowserFillTool(browser),
            BrowserPressTool(browser),
            BrowserWaitTool(browser),
            WorkspaceArchiveTool { [weak self] order in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.archiveWorkspaceForBridge(order)
            },
            WorkspaceMergeTool { [weak self] workspace, pullRequest, method in
                guard let self else {
                    return .refused("Unified Dev is still starting up. Try again in a moment.")
                }
                return await self.requestMergeForBridge(workspace, pullRequest, method: method)
            },
            RevealTool { [weak self] reveal in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.revealForBridge(reveal)
            },
            AgentStartTool { [weak self] order, sessionID, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.startCrewForBridge(order, from: sessionID, in: workspaceID)
            },
            AgentSayTool { [weak self] name, text, sessionID, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.sayToCrewForBridge(name, saying: text, from: sessionID, in: workspaceID)
            },
            AgentStopTool { [weak self] name, sessionID, workspaceID in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.stopCrewForBridge(name, from: sessionID, in: workspaceID)
            },
            WorkspaceSayTool { [weak self] message in
                guard let self else { return .refused("Unified Dev is still starting up.") }
                return await self.deliverWorkspaceMessage(message)
            },
        ])
    }

    private func archiveWorkspaceForBridge(_ order: WorkspaceArchiveOrder) async -> WorkspaceArchiveOutcome {
        guard let current = workspaces.first(where: { $0.id == order.workspace.id }) else {
            return .refused("This workspace is no longer active. Refresh workspace_list.")
        }
        guard let sessionID = order.afterTurnOf else {
            return await archive(current, deleteBranch: false, allowsConfirmation: false)
        }
        return bookArchiveForBridge(of: current, after: sessionID)
    }

    func showMediaForBridge(
        _ order: MediaShowOrder, in workspaceID: WorkspaceID
    ) -> MediaShowOutcome {
        guard let model = paneTarget(workspaceID) else {
            return .refused(Self.noWorkspaceForPane)
        }
        guard let media = WorkspaceMedia.resolve(path: order.path, in: model.workspace.path) else {
            return .refused(
                "That is not an image or video file inside this workspace. Save it in the "
                    + "workspace, then call media_show with that path."
            )
        }
        let noun = media.kind == .image ? "image" : "video"
        return .shown("Showing \(noun) '\(media.relativePath)' inline in the chat.")
    }

    func revealForBridge(_ reveal: RevealPlan) -> RevealOutcome {
        switch reveal.target {
        case .workspace(let id):
            guard workspaces.contains(where: { $0.id == id }) else {
                return .refused("That workspace is not in Unified Dev any more.")
            }
            selection = .workspace(id)
        case .home(let filter):
            homeFilter = filter
            selection = .home
        }
        return .revealed(reveal.sentence)
    }

    private func requestMergeForBridge(
        _ workspace: Workspace,
        _ pullRequest: PullRequest,
        method: GitHub.MergeMethod
    ) async -> WorkspaceMergeHandoff {
        let model = self.model(for: workspace)
        if let refusal = await model.requestMerge(pullRequest, method: method, from: .agentThroughBridge) {
            return .refused(refusal)
        }
        return .turnBegun(chat: model.activeSession?.title ?? "Merge")
    }

    func startWorkspaceForBridge(
        _ order: AgentWorkspaceOrder,
        in repo: Repo,
        from identity: BridgeIdentity,
        origin: WorkspaceOrigin
    ) async throws -> StartedWorkspaceSummary {
        guard let store else { throw AppNotReady.stillStartingUp }

        var controls = ComposerControls()
        if let sessionID = identity.sessionID, let session = try await store.session(id: sessionID) {
            let contextWindow = CodexContextWindow.normalised(try await store.setting(
                ComposerControls.contextWindowKey(sessionID: sessionID)
            ))
            let codexFastMode = CodexSpeed.override(stored: try await store.setting(CodexSpeed.key(sessionID: sessionID)))
            controls = ComposerControls(
                session: session,
                isFastMode: false,
                outputStyle: OutputStyle.defaultName,
                codexContextWindow: contextWindow,
                codexFastMode: codexFastMode
            )
        }
        controls = try await workspaceControls(for: order, in: repo, inheriting: controls)

        let workspace = try await startWorkspace(
            in: repo,
            prompt: order.prompt,
            baseBranch: order.source.baseBranch,
            branch: nil,
            controls: controls,
            select: false,
            origin: origin,
            name: order.name,
            checkout: order.source.checkout
        )

        return StartedWorkspaceSummary(
            workspaceID: workspace.id,
            name: workspace.name,
            branch: workspace.branch,
            path: workspace.path
        )
    }

    private func workspaceControls(
        for order: AgentWorkspaceOrder,
        in repo: Repo,
        inheriting inherited: ComposerControls
    ) async throws -> ComposerControls {
        var controls = inherited
        let inheritedAgent = controls.agentKind
        let agent = order.agent
            ?? order.model.map {
                ComposerModelCatalog.shared.backend(ofModel: $0, current: inheritedAgent)
            }
            ?? inheritedAgent
        controls.agentKind = agent

        if agent == .claudeCode {
            let models = Set(ComposerModelCatalog.shared.options(for: .claudeCode).map(\.id))
            if let model = order.model {
                guard models.contains(model) else {
                    throw BridgeWorkspaceModelFailure.invalid(
                        model: model,
                        agent: agent,
                        available: models.sorted()
                    )
                }
                controls.model = model
            }
            if order.model == nil, agent != inheritedAgent {
                controls.model = AppDefaults.fallbackModel
            }
        } else {
            let account = try await account(for: agent, in: AccountScope(workspaceID: nil, repoID: repo.id))
            guard let source = AgentModelSource.live(
                store: store, accounts: account.map { [agent: $0] } ?? [:]
            )[agent] else {
                throw BridgeWorkspaceModelFailure.noneAvailable(agent)
            }
            if order.model == nil, agent == inheritedAgent { return controls }

            let models = try await source.models()
            guard let chosen = AgentModel.selection(requested: order.model, from: models) else {
                if let requested = order.model {
                    throw BridgeWorkspaceModelFailure.invalid(
                        model: requested,
                        agent: agent,
                        available: models.filter { !$0.hidden }.map(\.id)
                    )
                }
                throw BridgeWorkspaceModelFailure.noneAvailable(agent)
            }
            controls.model = chosen.id
            controls.effort = DefaultBackend.effort(
                controls.effort, on: agent, model: chosen.id, models: [agent: models]
            )
        }

        return controls
    }

    static let noWorkspaceForCrew =
        "That workspace is not open in Unified Dev any more, so there is no worktree to run a subagent in."

    func startCrewForBridge(
        _ order: CrewOrder, from sessionID: SessionID, in workspaceID: WorkspaceID
    ) async -> CrewStartOutcome {
        guard let model = paneTarget(workspaceID) else { return .refused(Self.noWorkspaceForCrew) }
        return await model.startCrewMember(order, reportingTo: sessionID)
    }

    private func sayToCrewForBridge(
        _ name: String?, saying text: String, from sessionID: SessionID, in workspaceID: WorkspaceID
    ) async -> CrewSayOutcome {
        guard let model = paneTarget(workspaceID) else { return .refused(Self.noWorkspaceForCrew) }
        return await model.sayToCrew(text, to: name, from: sessionID)
    }

    private func stopCrewForBridge(
        _ name: String, from sessionID: SessionID, in workspaceID: WorkspaceID
    ) async -> CrewStopOutcome {
        guard let model = paneTarget(workspaceID) else { return .refused(Self.noWorkspaceForCrew) }
        return await model.stopCrewMember(named: name, startedBy: sessionID)
    }

    func paneTarget(_ workspaceID: WorkspaceID) -> WorkspaceModel? {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return nil }
        return model(for: workspace)
    }

    static let noWorkspaceForPane =
        "That workspace is not open in Unified Dev any more, so there is nowhere to put a pane."

    func openPaneForBridge(_ order: PaneOrder, in workspaceID: WorkspaceID) async -> PaneOutcome {
        guard let model = paneTarget(workspaceID) else { return .refused(Self.noWorkspaceForPane) }
        let tabs = WorkspaceTabsStore.shared
        let front = tabs.selectedTab(in: model)
        let activeSession = model.activeSessionID
        let placement = order.placement(hasTabInFront: front != nil)
        if case .refused(let sentence) = placement { return .refused(sentence) }
        NewPane.open(order.kind, in: model, url: order.url ?? "", title: order.title, browserAccess: .agents) { content in
            switch placement {
            case .front: tabs.select(content, in: model)
            case .behind:
                if model.activeSessionID != activeSession { model.activeSessionID = activeSession }
                if let front { tabs.select(front, in: model) }
            case .refused: break
            }
        }
        return .opened(order.confirmation(for: placement))
    }

    private func paneForBridge(
        _ kind: PaneKind?, in tab: PaneContent, of workspaceID: WorkspaceID, verb: String
    ) -> Result<String, PaneRefusal> {
        let tabs = WorkspaceTabsStore.shared
        let isOwners = { (pane: String) in
            self.isOwnersBrowser(tabs.content(of: pane, in: tab), in: workspaceID)
        }
        let ownersRefusal = PaneRefusal(BrowserPaneAccess.paneRefusal(verb: verb))
        guard let kind else {
            let focused = tabs.focusedPane(of: tab)
            return isOwners(focused) ? .failure(ownersRefusal) : .success(focused)
        }
        let matching = tabs.layout(of: tab).panes.filter {
            paneKind(of: tabs.content(of: $0, in: tab), in: workspaceID) == kind
        }
        if !matching.isEmpty, matching.allSatisfy(isOwners) { return .failure(ownersRefusal) }
        guard let found = matching.first(where: { !isOwners($0) }) else {
            return .failure(
                PaneRefusal(
                    "There is no \(kind.title.lowercased()) open in the tab in front. Nothing was "
                        + verb + "."
                )
            )
        }
        return .success(found)
    }

    func closePaneForBridge(_ target: PaneCloseTarget, in workspaceID: WorkspaceID) async -> PaneOutcome {
        guard let model = paneTarget(workspaceID) else { return .refused(Self.noWorkspaceForPane) }
        let kind: PaneKind?
        switch target {
        case .canvas: return await closeCanvasForBridge(in: model)
        case .focused: kind = nil
        case .pane(let named): kind = named
        }
        let tabs = WorkspaceTabsStore.shared
        guard let tab = tabs.selectedTab(in: model) else {
            return .refused("There is nothing open in that workspace to close.")
        }

        let layout = tabs.layout(of: tab)
        let pane: String
        switch paneForBridge(kind, in: tab, of: model.workspace.id, verb: "closed") {
        case .failure(let refusal): return .refused(refusal.sentence)
        case .success(let found): pane = found
        }

        guard layout.panes.count > 1 else {
            return .refused(Self.onlyPaneOpen)
        }

        guard tabs.close(pane: pane, in: tab, of: model.workspace.id) else {
            return .refused("Unified Dev could not close that pane.")
        }
        return .opened(kind.map { "Closed the \($0.title.lowercased())." } ?? "Closed that pane.")
    }

    private static let onlyPaneOpen =
        "That is the only pane open, and Unified Dev will not leave the centre column empty. "
            + "Open something else first, or leave this one."

    private func closeCanvasForBridge(in model: WorkspaceModel) async -> PaneOutcome {
        let centre = CenterTabStore.shared
        guard let canvas = centre.canvas(for: model.workspace.id) else {
            return .refused("There is no canvas open in this workspace. Nothing was closed.")
        }
        guard WorkspaceTabsStore.shared.entries(in: model) != [.tool(canvas.id)] else {
            return .refused(Self.onlyPaneOpen)
        }
        await centre.close(canvas, in: model)
        return .opened("Closed the canvas.")
    }

    func renamePaneForBridge(
        _ title: String, kind: PaneKind?, in workspaceID: WorkspaceID
    ) async -> PaneOutcome {
        guard let model = paneTarget(workspaceID) else { return .refused(Self.noWorkspaceForPane) }
        let tabs = WorkspaceTabsStore.shared
        guard let tab = tabs.selectedTab(in: model) else {
            return .refused("There is nothing open in that workspace to rename.")
        }

        let pane: String
        switch paneForBridge(kind, in: tab, of: model.workspace.id, verb: "renamed") {
        case .failure(let refusal): return .refused(refusal.sentence)
        case .success(let found): pane = found
        }

        switch tabs.content(of: pane, in: tab) {
        case .tool(let id):
            let centre = CenterTabStore.shared
            guard let target = centre.tabs(for: workspaceID).first(where: { $0.id == id }) else {
                return .refused("That pane is not in the strip any more, so it was not renamed.")
            }
            centre.rename(target, to: title)

        case .chat(let sessionID):
            guard let store,
                  let session = model.sessions.first(where: { $0.id == sessionID })
            else {
                return .refused("That chat is not open any more, so it was not renamed.")
            }
            let updated = session.with { $0.title = title }
            if let index = model.sessions.firstIndex(where: { $0.id == session.id }) {
                model.sessions[index] = updated
            }
            try? await store.updateSessionPreferences(id: session.id, title: title)
            await model.reloadSessions()
        }

        return .opened("Renamed that pane to '\(title)'.")
    }

    private func isOwnersBrowser(_ content: PaneContent, in workspaceID: WorkspaceID) -> Bool {
        guard case .tool(let id) = content,
              let tab = CenterTabStore.shared.tabs(for: workspaceID).first(where: { $0.id == id })
        else { return false }
        return tab.kind == .browser && !tab.browserAccess.isOpenToAgents
    }

    private func paneKind(of content: PaneContent, in workspaceID: WorkspaceID) -> PaneKind? {
        switch content {
        case .chat: return .chat
        case .tool(let id):
            let tabs = CenterTabStore.shared.tabs(for: workspaceID)
            guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
            switch tab.kind {
            case .terminal: return .terminal
            case .browser: return .browser
            case .review, .notes, .canvas: return nil
            }
        }
    }
}

private enum BridgeWorkspaceModelFailure: LocalizedError {
    case invalid(model: String, agent: AgentKind, available: [String])
    case noneAvailable(AgentKind)

    var errorDescription: String? {
        switch self {
        case let .invalid(model, agent, available):
            let choices = available.isEmpty ? "none were reported" : available.joined(separator: ", ")
            return "The model '\(model)' is not available for \(agent.label). Available models: \(choices)."
        case .noneAvailable(let agent):
            return "Unified Dev could not find an available model for \(agent.label)."
        }
    }
}

import AppKit
import SwiftUI
import Core

@MainActor
enum SearchPanelActivation {
    static func open(
        _ row: SearchPanelRow, panel: SearchPanelModel, app: AppModel
    ) {
        let mode = panel.field.mode
        panel.close(app: app)

        switch row {
        case .workspace(let hit):
            open(hit, app: app)

        case .transcript(let hit):
            guard let match = hit.result.best else { return }
            Task { await app.open(match) }

        case .command(let hit):
            run(hit.item.action, mode: mode, panel: panel, app: app)

        case .profile(let hit):
            Task { await app.switchProfile(to: hit.profile.id) }
        }
    }

    private static func open(_ hit: SearchPanelWorkspaceHit, app: AppModel) {
        if hit.isArchived {
            app.openArchived(hit.workspace)
        } else {
            app.selection = .workspace(hit.workspace.id)
        }
    }

    private static func run(
        _ action: MenuBarAction, mode: SearchPanelMode, panel: SearchPanelModel, app: AppModel
    ) {
        if let id = mode.workspaceID,
           let workspace = app.workspaces.first(where: { $0.id == id })
               ?? panel.archived.first(where: { $0.id == id }),
           let workspaceAction = SearchPanelActions.workspaceAction(for: action) {
            SearchPanelWorkspaceCommands.perform(workspaceAction, on: workspace, app: app)
            return
        }

        DispatchQueue.main.async {
            MainMenuActions.perform(action)
        }
    }
}

@MainActor
enum SearchPanelWorkspaceCommands {
    static func perform(_ action: WorkspaceMenuAction, on workspace: Workspace, app: AppModel) {
        switch action {
        case .openInEditor:
            Reveal.inEditor(workspace.path, repo: workspace.repoID)
        case .revealInFinder:
            Reveal.inFinder(workspace.path)
        case .copyName:
            Clipboard.copy(workspace.name)
        case .copyBranchName:
            Clipboard.copy(workspace.branch)
        case .pin:
            Task { await app.togglePinned(workspace) }
        case .unreadMark:
            guard let mark = WorkspaceUnreadMark.action(for: workspace) else { return }
            Task { await app.setUnread(workspace, mark.unread) }
        case .rename:
            NotificationCenter.default.post(
                name: .unifieddevRenameWorkspace, object: nil,
                userInfo: [Notification.unifieddevWorkspaceIDKey: workspace.id.rawValue]
            )
        case .archive:
            Task { await app.archive(workspace) }
        case .restore:
            Task { await app.restore(workspace) }
        case .colour:
            break
        }
    }
}

import SwiftUI
import Core

struct WorkspaceMenuItems: View {
    var workspace: Workspace
    var onArchive: (() -> Void)?
    var onRename: (WorkspaceID) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        openInEditorItem
        openWorktreeInItem
        revealInFinderItem
        openInDefaultBrowserItem
        copyBranchItem
        setupItem
        Divider()
        WorkspacePinItem(workspace: workspace, app: app)
        WorkspaceUnreadItem(workspace: workspace, app: app)
        WorkspaceColourItem(workspace: workspace, app: app)
        renameItem
        orchestratorItem
        Divider()
        Button("Archive", role: .destructive) {
            if let onArchive {
                onArchive()
            } else {
                Task { await app.archive(workspace) }
            }
        }
    }

    private var orchestratorItem: some View {
        Button(workspace.isOrchestrator ? "Stop Being Orchestrator" : "Make Orchestrator") {
            Task { await app.setOrchestrator(workspace, !workspace.isOrchestrator) }
        }
    }

    private var renameItem: some View {
        Button("Rename") { onRename(workspace.id) }
    }

    private var openInEditorItem: some View {
        Button("Open in Editor") { Reveal.inEditor(workspace.path, repo: workspace.repoID) }
    }

    private var openWorktreeInItem: some View {
        OpenInMenu(target: .folder(workspace.path), noun: "Worktree")
            .environment(\.openInRepoID, workspace.repoID)
    }

    private var revealInFinderItem: some View {
        Button("Reveal in Finder") { Reveal.inFinder(workspace.path) }
    }

    private var openInDefaultBrowserItem: some View {
        Button(BrowserToolbar().openInDefaultBrowser.name) {
            let model = app.model(for: workspace)
            Task {
                let address = await model.browserAddress(readingWhatTheScriptsWrote: false)
                if let url = BrowserAddress.external(from: address) { NSWorkspace.shared.open(url) }
            }
        }
    }

    private var copyBranchItem: some View {
        Button("Copy Branch Name") { Clipboard.copy(workspace.branch) }
    }

    @ViewBuilder
    private var setupItem: some View {
        if let offer = SetupRunOffer.menuOffer(
            for: workspace,
            presence: app.setupScriptPresence,
            live: app.existingModel(for: workspace.id)?.setupRunLive
        ) {
            Button(offer.title) { app.askToRunSetup(workspace) }
                .disabled(!offer.isEnabled)
        }
    }
}

struct WorkspacePinItem: View {
    var workspace: Workspace
    var app: AppModel

    var body: some View {
        MenuCommand(.pin, alternate: workspace.pinned) {
            Task { await app.togglePinned(workspace) }
        }
        .disabled(workspace.isOrchestrator)
    }
}

struct WorkspaceUnreadItem: View {
    var workspace: Workspace
    var app: AppModel

    var body: some View {
        if let mark = WorkspaceUnreadMark.action(for: workspace) {
            MenuCommand(.unreadMark, alternate: mark == .markRead) {
                Task { await app.setUnread(workspace, mark.unread) }
            }
        }
    }
}

struct WorkspaceColourItem: View {
    var workspace: Workspace
    var app: AppModel

    var body: some View {
        Picker(MenuBarCatalogue[.colour].title, selection: selection) {
            Text("None").tag("")
            ForEach(WorkspaceColour.all) { colour in
                Label {
                    Text(colour.name)
                } icon: {
                    if let swatch = WorkspaceColourImage.of(colour.hex) {
                        Image(nsImage: swatch).renderingMode(.original)
                    }
                }
                .tag(colour.hex)
            }
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: { workspace.colour ?? "" },
            set: { hex in
                Task { await app.setColour(workspace, to: hex.isEmpty ? nil : hex) }
            }
        )
    }
}

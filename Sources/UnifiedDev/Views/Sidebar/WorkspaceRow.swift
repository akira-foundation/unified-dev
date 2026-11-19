import SwiftUI
import Core

struct WorkspaceRow: View {
    var workspace: Workspace
    var isRunning: Bool
    var isAwaitingPermission = false
    var isStarting = false
    var foldsMarkColumn = false
    var trailingRepo: Repo?
    @Binding var renaming: WorkspaceID?
    var onArchive: (Workspace) -> Void
    var onMenuArchive: (() -> Void)?
    var isArchiveActive = false
    @Binding var archiveRequest: ArchiveRequest?
    @Binding var menuArchiveRequest: ArchiveRequest?
    var onConfirmArchive: (ArchiveRequest) -> Void = { _ in }

    @Environment(AppModel.self) private var app

    private var subagentFailures: Int { app.subagentFailures(of: workspace.id) }
    @Environment(\.backgroundProminence) private var backgroundProminence
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovered = false
    @State private var draft = ""
    @State private var hasEnded = false
    @FocusState private var fieldFocused: Bool

    private var isRenaming: Bool { renaming == workspace.id }

    private var isEmphasized: Bool { backgroundProminence == .increased }

    var body: some View {
        let pullRequest = WorkspacePullRequests.shared.pullRequest(for: workspace.id)
        let status = WorkspaceStatus.resolve(
            workspace: workspace,
            isRunning: isRunning,
            pullRequest: pullRequest,
            isAwaitingPermission: isAwaitingPermission,
            isStarting: isStarting
        )
        let statusDescription = status.summary(pullRequest: pullRequest)

        Label {
            HStack(spacing: Metrics.spacing) {
                if isRenaming {
                    TextField("Workspace name", text: $draft)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Palette.textPrimary)
                        .focused($fieldFocused)
                        .onSubmit { end(.submitted) }
                        .onExitCommand { end(.escaped) }
                        .onChange(of: fieldFocused) { had, has in
                            guard had, !has else { return }
                            end(.focusLost)
                        }
                        .task {
                            draft = workspace.name
                            hasEnded = false
                            try? await Task.sleep(for: .milliseconds(30))
                            fieldFocused = true
                        }
                } else {
                    WorkspaceNameText(workspace, isUnread: workspace.unread)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    WorkspaceColourDot(
                        hex: workspace.colour,
                        accessibilityName: workspace.colourDescription
                    )

                    if let discovery = app.seaDiscoveries.label(for: workspace.id) {
                        Image(systemName: SeaDiscoveries.symbol)
                            .font(Typo.micro)
                            .foregroundStyle(isEmphasized ? Palette.textInverted : Palette.textTertiary)
                            .help(discovery)
                            .accessibilityLabel(discovery)
                    }

                    Spacer(minLength: Metrics.spacingSmall)

                    if workspace.pinned {
                        Image(systemName: "pin.fill")
                            .font(Typo.micro)
                            .foregroundStyle(
                                isEmphasized ? Palette.textInverted : Palette.textTertiary
                            )
                            .accessibilityLabel("Pinned")
                    }

                    if let mark = WorkSuggestionSidebarMark.label(undecided: app.undecidedSuggestions(in: workspace.id)) {
                        Image(systemName: WorkSuggestionSidebarMark.symbol)
                            .font(Typo.micro)
                            .foregroundStyle(isEmphasized ? Palette.textInverted : Palette.link)
                            .opacity(isHovered ? 0 : 1)
                            .help(mark)
                            .accessibilityLabel(mark)
                    }

                    if subagentFailures > 0 {
                        Label("\(subagentFailures)", systemImage: "xmark")
                            .font(Typo.micro)
                            .monospacedDigit()
                            .labelStyle(SubagentFailureLabelStyle())
                            .foregroundStyle(isEmphasized ? Palette.textInverted : Palette.negative)
                            .opacity(isHovered ? 0 : 1)
                            .accessibilityLabel(subagentFailures == 1
                                ? "1 subagent failed this turn"
                                : "\(subagentFailures) subagents failed this turn")
                    }

                    if workspace.hasDiff {
                        DiffStatLabel(
                            additions: workspace.additions,
                            deletions: workspace.deletions,
                            compact: true
                        )
                        .opacity(isHovered ? 0 : 1)
                    }

                    if let trailingRepo {
                        RepoIcon(repo: trailingRepo, size: Metrics.repoIconSmall)
                            .frame(width: SidebarMetrics.rowButton)
                            .opacity(isHovered ? 0 : 1)
                            .accessibilityHidden(true)
                    }
                }
            }
            .mask { trailingYield }
            .overlay(alignment: .trailing) { hoverControls }
            .animation(reduceMotion ? nil : Motion.hover, value: isHovered)
        } icon: {
            if let role = SidebarRoleMark.symbol(isOrchestrator: workspace.isOrchestrator, status: status) {
                WorkspaceRoleGlyph(symbol: role, isOnSelection: isEmphasized)
            } else {
                WorkspaceStatusGlyph(status: status, isOnSelection: isEmphasized)
            }
        }
        .labelStyle(SidebarRowLabelStyle(showsMark: !foldsMarkColumn))
        .accessibilityValue(statusDescription)
        .contentShape(Rectangle())
        .focusedValue(\.isTypingProse, fieldFocused)
        .onHover { isHovered = $0 }
        .task(id: workspace.id) {
            await WorkspacePullRequests.shared.holdDrawn(workspace.id)
        }
        .environment(\.isOnEmphasizedSelection, isEmphasized)
        .onChange(of: isRenaming) { was, now in
            guard was, !now else { return }
            end(.dismissed)
        }
    }

    private var controlsShown: Bool { (isHovered || isArchiveActive) && !isRenaming }

    private static let controlsWidth = SidebarMetrics.rowButton * 2

    private static let controlsFade: CGFloat = 12

    private var hoverControls: some View {
        HStack(spacing: 0) {
            moreMenu
            archiveButton
        }
        .opacity(controlsShown ? 1 : 0)
        .allowsHitTesting(controlsShown)
    }

    private var trailingYield: some View {
        Rectangle()
            .overlay(alignment: .trailing) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(
                            color: .black,
                            location: Self.controlsFade / (Self.controlsFade + Self.controlsWidth)
                        ),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Self.controlsFade + Self.controlsWidth)
                .blendMode(.destinationOut)
                .opacity(controlsShown ? 1 : 0)
            }
            .compositingGroup()
    }

    private var moreMenu: some View {
        Menu {
            WorkspaceMenuItems(workspace: workspace, onArchive: onMenuArchive) { renaming = $0 }
        } label: {
            Label("More for \(workspace.name)", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .font(Typo.caption)
                .frame(width: SidebarMetrics.rowButton, height: SidebarMetrics.rowButton)
                .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerSmall))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(isEmphasized ? Palette.textInverted : Palette.textSecondary)
        .help("More for this workspace")
        .archiveConfirmation($menuArchiveRequest, arrowEdge: .leading, onConfirm: onConfirmArchive)
    }

    private var archiveButton: some View {
        Button {
            onArchive(workspace)
        } label: {
            Image(systemName: "archivebox")
                .font(Typo.caption)
                .frame(width: SidebarMetrics.rowButton, height: SidebarMetrics.rowButton)
                .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerSmall))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEmphasized ? Palette.textInverted : Palette.textSecondary)
        .help(MenuBarCatalogue[.archive].help("Archive workspace"))
        .accessibilityLabel("Archive \(workspace.name)")
        .archiveConfirmation($archiveRequest, arrowEdge: .leading, onConfirm: onConfirmArchive)
    }

    private func end(_ ending: InPlaceRename.Ending) {
        guard !hasEnded else { return }
        hasEnded = true
        if renaming == workspace.id { renaming = nil }
        guard case .commit(let name) = InPlaceRename.outcome(
            ending, draft: draft, current: workspace.name
        ) else { return }
        Task { await app.rename(workspace, to: name) }
    }
}

private struct SubagentFailureLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Metrics.spacingTight) {
            configuration.icon
            configuration.title
        }
    }
}

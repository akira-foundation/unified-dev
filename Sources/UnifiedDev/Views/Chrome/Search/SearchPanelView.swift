import SwiftUI
import Core

struct SearchPanelView: View {
    var app: AppModel
    @Bindable var panel: SearchPanelModel

    var width: CGFloat

    private static let listHeight: CGFloat = 310

    private static let fade: CGFloat = 28

    var body: some View {
        MenuPanel {
            field
            Hairline()

            if panel.field.mode.showsScopes, !panel.field.isEmpty {
                SearchPanelScopes(counts: panel.listing.counts, scope: scopeBinding)
                    .padding(.top, Metrics.spacingSmall)
            }

            list

            SearchPanelFooter(
                keys: SearchPanelKeys.footer(
                    for: panel.field.mode, isSearching: !panel.field.isEmpty
                ),
                summary: panel.listing.summary
            )
        }
        .frame(width: width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Search")
    }

    private var field: some View {
        HStack(spacing: Metrics.spacing) {
            Image(systemName: "magnifyingglass")
                .font(Typo.labelEmphasis)
                .foregroundStyle(Palette.textTertiary)

            if let pill = modePill {
                Chip(text: pill)
            }

            MenuSearchField(
                text: textBinding,
                placeholder: placeholder,
                onKey: key(_:),
                onBacktab: { handle(.backTab) },
                onDeleteEmpty: { handle(.backspaceOnEmpty) },
                onRight: { atEnd in
                    panel.caretAtEnd = atEnd
                    return handle(.right)
                },
                selectAllToken: panel.selectAllToken
            )
            .frame(height: Metrics.controlHeight)

            if let subject = commandSubject {
                Text("on \(subject)")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Metrics.inset)
        .padding(.vertical, Metrics.spacingWide)
    }

    private var modePill: String? {
        switch panel.field.mode {
        case .things: nil
        case .commands: SearchPanelMode.commands.pill
        case .actions: panel.drilledWorkspace(app: app)?.name ?? SearchPanelMode.actions(WorkspaceID("")).pill
        }
    }

    private var commandSubject: String? {
        guard panel.field.mode == .commands else { return nil }
        return app.menuWorkspace?.name
    }

    private var placeholder: String {
        switch panel.field.mode {
        case .things: "Search workspaces, profiles, transcripts and commands"
        case .commands: "Run a command"
        case .actions: "Act on this workspace"
        }
    }

    @ViewBuilder
    private var list: some View {
        Group {
            if let nothing = panel.listing.nothing {
                SearchPanelNothingView(
                    nothing: nothing, isIndexing: app.isTranscriptIndexIncomplete
                )
            } else {
                rows
            }
        }
        .frame(height: Self.listHeight)
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SearchPanelRowMetrics.gap) {
                    ForEach(panel.listing.sections) { section in
                        if let title = section.title {
                            Text(title)
                                .font(Typo.micro)
                                .foregroundStyle(Palette.textTertiary)
                                .padding(.horizontal, Metrics.inset)
                                .padding(.top, Metrics.gutter)
                                .padding(.bottom, Metrics.spacingTight)
                        }

                        ForEach(section.rows) { row in
                            self.row(row)
                                .id(row.id)
                        }
                    }
                }
                .padding(.top, Metrics.spacingSmall)
                .padding(.bottom, Self.fade)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .mask { fadeMask }
            .onChange(of: panel.highlighted) { _, index in
                guard let row = panel.listing.row(at: index) else { return }
                proxy.scrollTo(row.id)
            }
        }
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 1 - Self.fade / Self.listHeight),
                .init(color: .black.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func row(_ row: SearchPanelRow) -> some View {
        let index = panel.listing.rows.firstIndex { $0.id == row.id }
        let isSelected = index != nil && index == panel.highlighted

        switch row {
        case .workspace(let hit):
            SearchPanelWorkspaceRow(
                hit: hit,
                isSelected: isSelected,
                onPick: { open(row) },
                onHover: { panel.highlighted = index }
            )

        case .transcript(let hit):
            SearchPanelTranscriptRow(
                hit: hit,
                isSelected: isSelected,
                onPick: { open(row) },
                onHover: { panel.highlighted = index }
            )

        case .command(let hit):
            SearchPanelCommandRow(
                hit: hit,
                isEnabled: isRunnable(hit),
                isSelected: isSelected,
                onPick: { open(row) },
                onHover: { panel.highlighted = index }
            )

        case .profile(let hit):
            SearchPanelProfileRow(
                hit: hit,
                isSelected: isSelected,
                onPick: { open(row) },
                onHover: { panel.highlighted = index }
            )
        }
    }

    private func isRunnable(_ hit: SearchPanelCommandHit) -> Bool {
        panel.field.mode.workspaceID != nil || panel.runnable.contains(hit.item.action)
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { panel.field.text },
            set: { panel.type($0, app: app) }
        )
    }

    private var scopeBinding: Binding<HomeScope> {
        Binding(
            get: { panel.scope },
            set: { panel.setScope($0, app: app) }
        )
    }

    private func open(_ row: SearchPanelRow) {
        SearchPanelActivation.open(row, panel: panel, app: app)
    }

    private func key(_ key: ComposerKey) -> Bool {
        switch key {
        case .up: handle(.up)
        case .down: handle(.down)
        case .tab: handle(.tab)
        case .returnKey: handle(.returnKey)
        case .commandReturn: handle(.commandReturn)
        case .escape: handle(.escape)
        }
    }

    private func handle(_ key: SearchPanelKey) -> Bool {
        switch SearchPanelKeys.outcome(for: key, in: panel.keyContext) {
        case .move(let index):
            panel.highlighted = index
            return true
        case .open:
            guard let row = panel.listing.row(at: panel.highlighted) else { return true }
            open(row)
            return true
        case .drill:
            return panel.drill(app: app)
        case .scope(let scope):
            panel.setScope(scope, app: app)
            return true
        case .leaveMode:
            return panel.leaveMode(app: app)
        case .clearQuery:
            panel.clearQuery(app: app)
            return true
        case .close:
            panel.close(app: app)
            return true
        case .handled:
            return true
        case .ignored:
            return false
        }
    }
}

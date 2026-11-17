import SwiftUI
import Core

struct SidebarStatusBar: View {
    @Environment(AppModel.self) private var app

    @Binding var filter: SidebarFilter
    @AppStorage(ProjectVisibility.showsHiddenKey) private var showsHiddenProjects = false
    @AppStorage(SidebarGrouping.storageKey) private var storedGrouping = SidebarGrouping.standard.rawValue
    var note: String?
    var onNewWorkspace: () -> Void
    var onStartProject: () -> Void

    @State private var isShowingLegend = false
    @State private var fixedWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            HStack(spacing: Metrics.spacing) {
                filterMenu
                newWorkspaceButton
                startProjectButton
                legendButton
            }
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fixedWidth = $0 }

            notePill
        }
        .preference(key: SidebarFooterWidth.self, value: fixedWidth + 2 * Metrics.spacing)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.spacing)
        .padding(.top, Metrics.spacingSmall)
        .padding(.bottom, Metrics.spacing)
    }

    private var filterMenu: some View {
        Menu {
            SidebarFilterMenuItems(
                filter: $filter,
                showsHiddenProjects: $showsHiddenProjects,
                hiddenCount: ProjectVisibility.hiddenCount(app.profileRepos),
                grouping: groupingChoice
            )
        } label: {
            pill(isRound: true) {
                ComposerControlLabel(
                    systemImage: filter == .all ? "line.3.horizontal.decrease" : filter.icon,
                    text: nil
                )
                .foregroundStyle(Palette.textSecondary)
            }
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter the sidebar")
        .accessibilityLabel("Filter the sidebar")
        .accessibilityValue(filterValue)
    }

    private var newWorkspaceButton: some View {
        Button(action: onNewWorkspace) {
            pill {
                ComposerControlLabel(systemImage: "square.and.pencil", text: "New workspace")
            }
            .foregroundStyle(app.profileRepos.isEmpty ? Palette.textDisabled : Palette.textSecondary)
        }
        .disabled(app.profileRepos.isEmpty)
        .help("New workspace (\(MenuBarCatalogue[.newWorkspace].keyText))")
        .accessibilityLabel("New workspace")
    }

    private var startProjectButton: some View {
        Button(action: onStartProject) {
            pill(isRound: true) {
                ComposerControlLabel(systemImage: "folder.badge.plus", text: nil)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .help("\(MenuBarCatalogue[.startProject].title) (\(MenuBarCatalogue[.startProject].keyText))")
        .accessibilityLabel(MenuBarCatalogue[.startProject].title)
    }

    private var legendButton: some View {
        Button {
            isShowingLegend.toggle()
        } label: {
            pill(isRound: true) {
                ComposerControlLabel(systemImage: "questionmark.circle", text: nil)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .help("What the sidebar glyphs mean")
        .accessibilityLabel("What the sidebar glyphs mean")
        .popover(isPresented: $isShowingLegend, arrowEdge: .top) {
            SidebarLegend()
        }
    }

    @ViewBuilder
    private var notePill: some View {
        if let note {
            pill {
                ComposerControlLabel(systemImage: "arrow.uturn.backward", text: note)
            }
            .foregroundStyle(Palette.textSecondary)
            .accessibilityLabel(note)
        }
    }

    private func pill<Content: View>(isRound: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, isRound ? 0 : Metrics.spacingSmall)
            .frame(width: isRound ? Metrics.barHeight : nil, height: Metrics.barHeight)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay { Capsule().strokeBorder(Palette.border, lineWidth: Metrics.outline) }
    }

    private var groupingChoice: Binding<SidebarGrouping> {
        let stored = $storedGrouping
        return Binding(
            get: { SidebarGrouping.resolve(stored.wrappedValue) },
            set: { stored.wrappedValue = $0.rawValue }
        )
    }

    private var filterValue: String {
        let shown = showsHiddenProjects ? "\(filter.rawValue), hidden projects showing" : filter.rawValue
        return SidebarGrouping.resolve(storedGrouping) == .status ? shown + ", grouped by status" : shown
    }
}

struct SidebarFooterWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

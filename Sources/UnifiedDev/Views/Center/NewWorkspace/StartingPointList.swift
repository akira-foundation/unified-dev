import SwiftUI
import Core

struct StartingPointList: View {
    var catalogue: WorkspaceSourceCatalogue
    var pullRequests: PullRequestLoad
    var leadingBases: [String]
    var onPick: @MainActor (WorkspaceSource) -> Void
    var onDismiss: @MainActor () -> Void

    @State private var query = ""
    @State private var selected: WorkspaceSource?

    private static let width: CGFloat = 460
    private static let listHeight: CGFloat = 360

    private var sections: [StartingPointSection] {
        StartingPointMenu.sections(
            offering: catalogue.offering,
            query: query,
            leadingBases: leadingBases,
            offersPullRequests: catalogue.offersPullRequests
        )
    }

    var body: some View {
        let sections = self.sections
        return VStack(alignment: .leading, spacing: 0) {
            searchRow
            Hairline()

            Group {
                if sections.isEmpty {
                    MenuEmptyRow(text: query.isEmpty ? "No branches to start from yet" : "Nothing matches \(query)")
                } else {
                    list(sections)
                }
            }
            .frame(height: Self.listHeight, alignment: .top)

            if catalogue.offersPullRequests, let note = pullRequests.note {
                Hairline()
                Text(note)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, Metrics.spacingWide)
            }
        }
        .frame(width: Self.width)
        .onAppear { selected = StartingPointMenu.rows(in: sections).first }
        .onChange(of: query) { _, typed in
            let current = self.sections
            selected = StartingPointMenu.jump(query: typed, in: current) ?? StartingPointMenu.rows(in: current).first
        }
    }

    private var searchRow: some View {
        HStack(spacing: Metrics.spacing) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(Palette.textTertiary)

            MenuSearchField(
                text: $query,
                placeholder: "Search branches and pull requests, or type #13",
                onKey: handle(key:)
            )
            .frame(height: Metrics.rowHeight)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.spacingSmall)
    }

    private func list(_ sections: [StartingPointSection]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                WorkspaceSourceRow(
                                    source: row,
                                    isSelected: row == selected,
                                    onPick: { onPick(row) },
                                    onHover: { selected = row }
                                )
                                .id(row.id)
                            }
                        } header: {
                            Text(section.title)
                                .font(Typo.caption)
                                .foregroundStyle(Palette.textTertiary)
                                .padding(.horizontal, Metrics.spacing)
                                .padding(.top, Metrics.spacingWide)
                                .padding(.bottom, Metrics.spacingTight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.surface)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                .padding(Metrics.spacingSmall)
            }
            .onChange(of: selected) { _, row in
                guard let row else { return }
                proxy.scrollTo(row.id)
            }
        }
    }

    private func handle(key: ComposerKey) -> Bool {
        switch key {
        case .up:
            selected = StartingPointMenu.stepped(from: selected, by: -1, in: sections)
            return true
        case .down:
            selected = StartingPointMenu.stepped(from: selected, by: 1, in: sections)
            return true
        case .returnKey, .commandReturn:
            guard let selected else { return false }
            onPick(selected)
            return true
        case .escape:
            onDismiss()
            return true
        case .tab:
            return false
        }
    }
}

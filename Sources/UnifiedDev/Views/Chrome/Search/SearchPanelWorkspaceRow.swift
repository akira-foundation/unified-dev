import SwiftUI
import Core

struct SearchPanelWorkspaceRow: View {
    var hit: SearchPanelWorkspaceHit
    var isSelected: Bool
    var onPick: @MainActor () -> Void
    var onHover: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: Metrics.spacingWide) {
                RepoIcon(repo: hit.repo)

                VStack(alignment: .leading, spacing: SearchPanelRowMetrics.lineGap) {
                    name
                        .font(Typo.bodyEmphasis)
                        .lineLimit(1)
                    detail
                        .font(Typo.caption)
                        .foregroundStyle(SearchPanelRowInk.detail(isSelected: isSelected).colour)
                        .lineLimit(1)
                }

                Spacer(minLength: Metrics.spacingWide)
            }
            .searchPanelRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .searchPanelRowPlate(isSelected: isSelected, isHovered: isHovered)
        .onHoverChange { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
    }

    private var name: Text {
        let ink = SearchPanelRowInk.title(isEnabled: true).colour
        return MatchedRuns.text(hit.workspace.name, highlights: hit.highlights, loud: ink, quiet: ink)
    }

    private var detail: Text {
        var parts: [String] = [hit.repo?.name ?? "Unknown project"]
        if hit.isArchived { parts.append("archived") }
        if let waiting = hit.waiting { parts.append(waiting.label) }
        if let match = hit.match { parts.append(match) }
        parts.append(
            hit.workspace.lastActivityAt.formatted(
                .relative(presentation: .numeric, unitsStyle: .narrow)
            )
        )
        return Text(parts.joined(separator: " \u{00B7} "))
    }

    private var accessibilityLabel: String {
        var parts = [hit.workspace.name]
        if let repo = hit.repo { parts.append("in \(repo.name)") }
        if hit.isArchived { parts.append("archived") }
        if let waiting = hit.waiting { parts.append(waiting.label) }
        if let match = hit.match { parts.append("matched \(match)") }
        return parts.joined(separator: ", ")
    }
}

import SwiftUI
import Core

struct SearchPanelTranscriptRow: View {
    var hit: SearchPanelTranscriptHit
    var isSelected: Bool
    var onPick: @MainActor () -> Void
    var onHover: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onPick) {
            HStack(alignment: .top, spacing: Metrics.spacingWide) {
                RepoIcon(repo: hit.repo)

                VStack(alignment: .leading, spacing: SearchPanelRowMetrics.lineGap) {
                    HStack(spacing: Metrics.spacingSmall) {
                        Text(hit.workspace?.name ?? "Unknown workspace")
                            .font(Typo.bodyEmphasis)
                            .foregroundStyle(SearchPanelRowInk.title(isEnabled: true).colour)
                            .lineLimit(1)

                        Text(detail)
                            .font(Typo.caption)
                            .foregroundStyle(SearchPanelRowInk.detail(isSelected: isSelected).colour)
                            .lineLimit(1)
                    }

                    if let snippet = hit.result.best?.snippet, !snippet.isEmpty {
                        Text(marked(snippet))
                            .font(Typo.caption)
                            .foregroundStyle(SearchPanelRowInk.detail(isSelected: isSelected).colour)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: Metrics.spacingWide)
            }
            .searchPanelRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the workspace at this point in the transcript.")
        .searchPanelRowPlate(isSelected: isSelected, isHovered: isHovered)
        .onHoverChange { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
    }

    private var detail: String {
        var parts = [hit.repo?.name ?? "Unknown project"]
        if hit.isArchived { parts.append("archived") }
        parts.append(hit.result.total == 1 ? "1 match" : "\(hit.result.total) matches")
        return parts.joined(separator: " \u{00B7} ")
    }

    private var accessibilityLabel: String {
        "\(hit.workspace?.name ?? "Unknown workspace"), \(detail)"
    }

    private func marked(_ snippet: TranscriptSnippet) -> AttributedString {
        var built = AttributedString()
        for segment in snippet.segments {
            var run = AttributedString(segment.text)
            if segment.isMatch {
                run.inlinePresentationIntent = .stronglyEmphasized
                run.foregroundColor = SearchPanelRowInk.title(isEnabled: true).colour
            }
            built.append(run)
        }
        return built
    }
}

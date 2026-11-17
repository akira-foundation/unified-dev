import SwiftUI
import Core

struct StartingPointSuggestionList: View {
    var suggestions: [StartingPointSuggestion]
    var point: WorkspaceStartingPoint
    var onPick: @MainActor (StartingPointSuggestion) -> Void

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 0) {
            Text("Start from")
                .font(Typo.caption)
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, Metrics.spacing)
                .padding(.bottom, Metrics.spacingTight)
                .accessibilityAddTraits(.isHeader)

            ForEach(suggestions) { suggestion in
                StartingPointSuggestionRow(
                    suggestion: suggestion,
                    reason: suggestion.reason(now: now),
                    isChosen: suggestion.isChosen(by: point),
                    onPick: { onPick(suggestion) }
                )
            }
        }
        .frame(maxWidth: TranscriptLayout.conversationMeasure, alignment: .leading)
        .padding(.horizontal, ComposerLayout.horizontalInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested starting points")
    }
}

private struct StartingPointSuggestionRow: View {
    var suggestion: StartingPointSuggestion
    var reason: String
    var isChosen: Bool
    var onPick: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: Metrics.spacing) {
                Image(systemName: suggestion.glyph)
                    .imageScale(.small)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: Metrics.glyph)

                Text(suggestion.title)
                    .font(Typo.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let reference = suggestion.reference {
                    Text(reference)
                        .font(Typo.codeSmall)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize()
                }

                Spacer(minLength: Metrics.spacingSmall)

                Text(reason)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)

                if isChosen {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Metrics.spacing)
            .frame(minHeight: Metrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowBackground(isSelected: false, isHovered: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityLabel(suggestion.spoken)
        .accessibilityValue(isChosen ? "\(reason), chosen" : reason)
    }
}

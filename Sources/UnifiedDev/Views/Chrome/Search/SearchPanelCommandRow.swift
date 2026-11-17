import SwiftUI
import Core

struct SearchPanelCommandRow: View {
    var hit: SearchPanelCommandHit
    var isEnabled: Bool
    var isSelected: Bool
    var onPick: @MainActor () -> Void
    var onHover: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: Metrics.spacingWide) {
                title
                    .font(Typo.body)
                    .lineLimit(1)

                Spacer(minLength: Metrics.gutter)

                Text(hit.item.keyText)
                    .font(Typo.caption)
                    .foregroundStyle(SearchPanelRowInk.detail(isSelected: isSelected, isEnabled: isEnabled).colour)
                    .lineLimit(1)
            }
            .searchPanelRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(SearchPanelUndimmedButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(hit.item.title)
        .accessibilityValue(hit.item.keyText)
        .searchPanelRowPlate(isSelected: isSelected, isHovered: isHovered)
        .onHoverChange { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
    }

    private var title: Text {
        let ink = SearchPanelRowInk.title(isEnabled: isEnabled).colour
        return MatchedRuns.text(hit.item.title, highlights: hit.highlights, loud: ink, quiet: ink)
    }
}

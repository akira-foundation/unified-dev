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
                MatchedRuns.text(hit.item.title, highlights: hit.highlights)
                    .font(Typo.body)
                    .searchPanelInk(SearchPanelRowInk.title(isEnabled: isEnabled))
                    .lineLimit(1)

                Spacer(minLength: Metrics.gutter)

                if let keyText = hit.item.keyText {
                    Text(keyText)
                        .font(Typo.body)
                        .searchPanelInk(SearchPanelRowInk.detail(isEnabled: isEnabled))
                        .lineLimit(1)
                }
            }
            .searchPanelRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(SearchPanelUndimmedButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(hit.item.title)
        .accessibilityValue(hit.item.keyText ?? "")
        .searchPanelRowPlate(isSelected: isSelected, isHovered: isHovered)
        .onHoverChange { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
    }
}

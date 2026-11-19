import SwiftUI
import Core

struct SearchPanelProfileRow: View {
    var hit: SearchPanelProfileHit
    var isSelected: Bool
    var onPick: @MainActor () -> Void
    var onHover: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: Metrics.spacingWide) {
                ProfileMark(symbol: hit.profile.symbol, colour: hit.profile.colour)
                    .frame(width: Metrics.repoIcon, height: Metrics.repoIcon)

                VStack(alignment: .leading, spacing: SearchPanelRowMetrics.lineGap) {
                    MatchedRuns.text(hit.profile.name, highlights: hit.highlights)
                        .font(Typo.bodyEmphasis)
                        .searchPanelInk(SearchPanelRowInk.title(isEnabled: true))
                        .lineLimit(1)
                    Text(SearchPanelProfiles.detail)
                        .font(Typo.caption)
                        .searchPanelInk(SearchPanelRowInk.detail())
                        .lineLimit(1)
                }

                Spacer(minLength: Metrics.spacingWide)

                if let keyText = hit.keyText {
                    Text(keyText)
                        .font(Typo.body)
                        .searchPanelInk(SearchPanelRowInk.detail())
                        .lineLimit(1)
                }
            }
            .searchPanelRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch to the profile \(hit.profile.name)")
        .accessibilityValue(hit.keyText ?? "")
        .searchPanelRowPlate(isSelected: isSelected, isHovered: isHovered)
        .onHoverChange { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
    }
}

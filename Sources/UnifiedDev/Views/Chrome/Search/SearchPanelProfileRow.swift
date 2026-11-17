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
                    name
                        .font(Typo.bodyEmphasis)
                        .lineLimit(1)
                    Text(SearchPanelProfiles.detail)
                        .font(Typo.caption)
                        .foregroundStyle(SearchPanelRowInk.detail(isSelected: isSelected).colour)
                        .lineLimit(1)
                }

                Spacer(minLength: Metrics.spacingWide)

                if let keyText = hit.keyText {
                    Text(keyText)
                        .font(Typo.caption)
                        .foregroundStyle(SearchPanelRowInk.detail(isSelected: isSelected).colour)
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

    private var name: Text {
        let ink = SearchPanelRowInk.title(isEnabled: true).colour
        return MatchedRuns.text(hit.profile.name, highlights: hit.highlights, loud: ink, quiet: ink)
    }
}

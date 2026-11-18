import SwiftUI
import Core

enum SearchPanelRowMetrics {
    static let plateInset: CGFloat = Metrics.spacing

    static let contentInset: CGFloat = Metrics.inset - plateInset

    static let air: CGFloat = Metrics.spacing

    static let gap: CGFloat = Metrics.spacingTight

    static let lineGap: CGFloat = Metrics.spacingTight
}

extension View {
    func searchPanelRowPadding() -> some View {
        padding(.horizontal, SearchPanelRowMetrics.contentInset)
            .padding(.vertical, SearchPanelRowMetrics.air)
    }

    func searchPanelRowPlate(isSelected: Bool, isHovered: Bool) -> some View {
        rowBackground(isSelected: isSelected, isHovered: isHovered, isFocused: true)
            .padding(.horizontal, SearchPanelRowMetrics.plateInset)
    }
}

extension View {
    func searchPanelInk(_ ink: SearchPanelRowInk) -> some View {
        modifier(SearchPanelInkStyle(ink: ink))
    }
}

private struct SearchPanelInkStyle: ViewModifier {
    var ink: SearchPanelRowInk

    @Environment(\.isOnEmphasizedSelection) private var isOnSelection

    func body(content: Content) -> some View {
        content.foregroundStyle(colour)
    }

    private var colour: Color {
        switch (ink, isOnSelection) {
        case (.primary, true): Palette.selectedEmphasizedText
        case (.secondary, true): Palette.selectedEmphasizedText.opacity(0.76)
        case (.tertiary, true): Palette.selectedEmphasizedText.opacity(0.55)
        case (.primary, false): Palette.textPrimary
        case (.secondary, false): Palette.textSecondary
        case (.tertiary, false): Palette.textTertiary
        }
    }
}

struct SearchPanelUndimmedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

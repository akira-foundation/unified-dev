import SwiftUI
import Core

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
        if isOnSelection {
            return Palette.selectedEmphasizedText.opacity(ink.opacityOnSelection)
        }
        return ink.isSecondaryOffSelection ? Palette.textSecondary : Palette.textPrimary
    }
}

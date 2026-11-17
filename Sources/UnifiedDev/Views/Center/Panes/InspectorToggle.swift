import SwiftUI
import Core

struct InspectorToggle: View {
    var visibility: InspectorVisibility
    var action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Label("Inspector", systemImage: "sidebar.trailing")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Inspector")
        .accessibilityValue(visibility.isVisible ? "Shown" : "Hidden")
        .help(visibility.toggleHelp)
    }
}

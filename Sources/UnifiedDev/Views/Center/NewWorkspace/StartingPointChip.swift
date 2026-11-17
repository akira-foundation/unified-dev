import SwiftUI
import Core

struct StartingPointChip: View {
    var point: WorkspaceStartingPoint
    var remote: String?
    var catalogue: WorkspaceSourceCatalogue?
    var pullRequests: PullRequestLoad
    var leadingBases: [String]
    @Binding var isPresented: Bool
    var onPick: @MainActor (WorkspaceSource) -> Void

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ComposerControlLabel(
                systemImage: StartingPointLabel.glyph(for: point),
                text: StartingPointLabel.text(for: point, remote: remote),
                isActive: isPresented,
                showsMenuIndicator: true
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .disabled(catalogue == nil)
        .help("Choose where the work starts: a new branch, a branch that exists, or a pull request")
        .accessibilityLabel(StartingPointLabel.accessibilityLabel)
        .accessibilityValue(StartingPointLabel.spoken(for: point, remote: remote))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            if let catalogue {
                StartingPointList(
                    catalogue: catalogue,
                    pullRequests: pullRequests,
                    leadingBases: leadingBases,
                    onPick: { source in
                        isPresented = false
                        onPick(source)
                    },
                    onDismiss: { isPresented = false }
                )
            }
        }
    }
}

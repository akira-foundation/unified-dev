import SwiftUI
import Core

struct StartProjectActions: View {
    var model: StartProjectModel
    var onStart: () -> Void
    var onClone: () -> Void
    var onStop: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: Metrics.spacingWide) {
            Spacer(minLength: 0)

            switch model.stage {
            case .landing:
                EmptyView()

            case .naming:
                back
                Button(model.verdict.buttonTitle, action: onStart)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.controlAccent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStart)

            case .cloning:
                back
                Button("Clone", action: onClone)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.controlAccent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canClone)

            case .creating, .fetching:
                Button("Stop", role: .cancel, action: onStop)
                    .keyboardShortcut(.cancelAction)

            case .failed(let fault):
                Button("Close", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
                if fault.hostOffer != nil {
                    Button("Back") { model.leave() }
                    Button("Trust and try again") { model.trustHostAndClone() }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.controlAccent)
                } else {
                    Button("Try again") { model.leave() }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.controlAccent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.inset)
    }

    private var back: some View {
        Button("Back", role: .cancel) { model.leave() }
            .keyboardShortcut(.cancelAction)
    }
}

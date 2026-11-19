import SwiftUI
import Core

struct DiffHunkHeaderView: View {
    var text: String
    var width: CGFloat
    var path = ""
    var discard: HunkDiscard.Availability = .hidden
    var hunk: DiffHunk?
    var isConfirming: Binding<Bool> = .constant(false)
    var staged: HunkDiscard.Staged = .clean
    var onAsk: () -> Void = {}
    var onRecheck: () -> Void = {}
    var onDiscard: () -> Void = {}

    private var filename: String { (path as NSString).lastPathComponent }

    var body: some View {
        HStack(spacing: InspectorLayout.gap) {
            Image(systemName: "curlybraces")
                .font(Typo.micro)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
                .font(Typo.codeTiny)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            discardButton
        }
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, CodeMetrics.textInset)
        .frame(width: width, height: CodeMetrics.rowHeight, alignment: .leading)
        .background(Palette.surfaceSunken)
        .onHover { inside in if inside { onRecheck() } }
    }

    @ViewBuilder
    private var discardButton: some View {
        switch discard {
        case .hidden:
            EmptyView()
        case .enabled:
            button(reason: nil)
        case let .disabled(reason):
            button(reason: reason)
        }
    }

    private func button(reason: String?) -> some View {
        let control = FileBarControls.discardHunk(filename: filename, blocker: reason)
        return Button(action: onAsk) {
            Label(control.title, systemImage: "arrow.uturn.backward")
                .font(Typo.micro)
        }
        .buttonStyle(.borderless)
        .controlSize(.mini)
        .labelStyle(.titleAndIcon)
        .disabled(reason != nil)
        .help(control.hint)
        .accessibilityHint(control.hint)
        .fixedSize()
        .discardConfirmation(
            isPresented: isConfirming,
            alert: { hunk.map { DiscardAlert.hunk($0, path: path, staged: staged) } },
            onConfirm: onDiscard
        )
    }
}

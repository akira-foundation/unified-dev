import SwiftUI
import Core

struct FileDiskChangeBand: View {
    let model: WorkspaceModel
    let path: String
    let absolutePath: String
    let session: FileEditSession
    let language: Language
    let canOverwrite: Bool
    var onSaved: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @State private var comparing = false
    @State private var isConfirmingReload = false

    private var filename: String { (path as NSString).lastPathComponent }

    var body: some View {
        HStack {
            Text("Changed on disk. Your edits are safe.").font(Typo.caption)
            Spacer()
            Button("Compare") { comparing = true }
        }
        .padding(InspectorLayout.inset)
        .sheet(isPresented: $comparing) { comparison }
        .discardDraftDialog(filename: filename, isPresented: $isConfirmingReload) {
            Task { await session.reload(path: absolutePath) }
        }
    }

    private var comparison: some View {
        VStack(spacing: Metrics.spacing) {
            Text("\(filename) changed on disk").font(Typo.bodyEmphasis)
            HSplitView {
                VStack {
                    Text("Your draft")
                    SourceEditor(text: session.binding(for: absolutePath), language: language, colorScheme: colorScheme,
                                 isEditable: canOverwrite)
                }
                VStack {
                    Text("Current file on disk")
                    SourceEditor(text: .constant(session.diskVersions[absolutePath]?.text ?? ""),
                                 language: language, colorScheme: colorScheme, isEditable: false)
                }
            }
            HStack {
                Button("Keep editing") { comparing = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use disk version") {
                    comparing = false
                    isConfirmingReload = true
                }
                .disabled(!canOverwrite)
                Button("Save my version over disk") {
                    Task {
                        guard await session.keepDraftOverDisk(path: absolutePath, reviewing: path, in: model) else {
                            return
                        }
                        comparing = false
                        onSaved()
                    }
                }
                .disabled(!canOverwrite)
            }
            if case let .failed(reason) = session.status(for: absolutePath) {
                Text(reason).foregroundStyle(Palette.negative).font(Typo.caption)
            }
        }.padding(Metrics.inset).frame(width: 950, height: 580)
    }
}

extension View {
    func discardDraftDialog(
        filename: String, isPresented: Binding<Bool>, discard: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Discard your edits to \(filename)?", isPresented: isPresented, titleVisibility: .visible
        ) {
            Button("Discard and reload", role: .destructive, action: discard)
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("The file on disk replaces what you typed. There is no undo for this.")
        }
    }
}

import SwiftUI
import Core

struct FileEditPane: View {
    let model: WorkspaceModel
    let path: String
    let session: FileEditSession
    var onSaved: () -> Void = {}
    var isEditable = true
    var canEdit = true
    var absolutePathOverride: String?

    @Environment(\.colorScheme) private var colorScheme

    @State private var isConfirmingReload = false

    private var absolutePath: String {
        absolutePathOverride ?? (model.workspace.path as NSString).appendingPathComponent(path)
    }

    private var state: SourceEditorState { SourceEditorState.file(absolutePath) }
    private var language: Language { state.languageOverride ?? Language.detect(path: path) }
    private var controls: FileTabDraftControls {
        session.controls(for: absolutePath, mode: isEditable ? .edit : .source, canEdit: canEdit)
    }

    private var filename: String { (path as NSString).lastPathComponent }

    private var isDirty: Bool { session.isDirty(absolutePath) }

    var body: some View {
        Group {
            switch session.status(for: absolutePath) {
            case .loading:
                LoadingView("Reading the file")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .unavailable(reason):
                EmptyStateView(
                    glyph: "doc.badge.gearshape",
                    title: isEditable ? "Cannot edit this file" : "Cannot read this file",
                    message: reason
                )
            default:
                editor
            }
        }
        .focusedValue(\.saveAction, canEdit ? SaveAction(subject: absolutePath, isEnabled: controls.canSave, perform: save) : nil)
        .focusedValue(\.isTypingProse, isEditable)
        .onDisappear { state.navigationTask?.cancel() }
        .discardDraftDialog(filename: filename, isPresented: $isConfirmingReload) {
            Task { await session.reload(path: absolutePath) }
        }
        .task(id: absolutePath) {
            await session.load(path: absolutePath)
            guard controls.watchesDisk else { return }
            await session.watch(path: absolutePath)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if session.draft(for: absolutePath) != nil {
            VStack(spacing: 0) {
                SourceTools(model: model, path: path, state: state)
                Hairline()
                SourceEditor(
                    text: session.binding(for: absolutePath),
                    language: language,
                    colorScheme: colorScheme,
                    isEditable: isEditable,
                    editorState: state,
                    onOpenReference: { SourceActions.open($0, at: $1, path: path, model: model, state: state, newTab: $2) },
                    onDefinition: { SourceActions.definition(at: $0, path: path, model: model, state: state) },
                    onReferences: { SourceActions.references(at: $0, path: path, model: model, state: state) },
                    onNavigateSymbol: { SourceActions.navigate(at: $0, path: path, model: model, state: state, newTab: $1) },
                    onAsk: { SourceActions.ask(path: path, model: model, state: state) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Hairline()
                if let message = state.message {
                    HStack {
                        Text(message).font(Typo.caption).textSelection(.enabled)
                        Spacer()
                        Button("Dismiss") { state.message = nil }
                    }.padding(InspectorLayout.inset)
                }
                if controls.showsDiskChange {
                    FileDiskChangeBand(
                        model: model, path: path, absolutePath: absolutePath, session: session,
                        language: language, canOverwrite: controls.canOverwriteDisk, onSaved: onSaved
                    )
                }
                if isEditable { footer } else if case let .failed(reason) = session.status(for: absolutePath) {
                    Text(reason).font(Typo.caption).foregroundStyle(Palette.negative).padding(InspectorLayout.inset)
                }
            }
        } else {
            LoadingView("Reading the file")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: InspectorLayout.gap) {
            statusLabel

            Spacer(minLength: InspectorLayout.tight)

            if isDirty {
                Button("Discard") { isConfirmingReload = true }
                    .disabled(session.saving.contains(absolutePath))
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Throw away your unsaved edits and read the file again")
            }

            Button("Save", action: save)
                .controlSize(.small)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!controls.canSave)
        }
        .padding(.horizontal, InspectorLayout.inset)
        .frame(height: InspectorLayout.barHeight)
        .background(Palette.surfaceSunken)
    }

    private func save() {
        Task {
            guard await session.save(path: absolutePath, reviewing: path, in: model) else { return }
            onSaved()
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch session.status(for: absolutePath) {
        case let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(Typo.caption)
                .foregroundStyle(Palette.negative)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        case .saved where !isDirty:
            Label("Saved", systemImage: "checkmark.circle")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
        default:
            Text(isDirty ? "Unsaved changes" : "No changes")
                .font(Typo.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

import SwiftUI
import Core

struct FilePreview: View {
    let model: WorkspaceModel
    let path: String
    var absolutePathOverride: String?
    var canEditInApp = true
    @State private var showsMarkdownPreview = false
    @State private var width: CGFloat = 0
    private let session = FileEditSession.shared

    private var absolutePath: String {
        absolutePathOverride ?? (model.workspace.path as NSString).appendingPathComponent(path)
    }
    private var state: SourceEditorState { SourceEditorState.file(absolutePath) }
    private var hasPreview: Bool { DocumentPreview.hasPreview(path: path) }
    private var modes: [FileTabMode] { FileTabMode.choices(hasPreview: hasPreview, canEdit: canEditInApp) }
    private var mode: FileTabMode {
        FileTabMode.current(
            prefersEditing: state.prefersEditing, prefersPreview: state.prefersPreview,
            hasPreview: hasPreview, canEdit: canEditInApp
        )
    }
    private var controls: FileTabDraftControls {
        session.controls(for: absolutePath, mode: mode, canEdit: canEditInApp)
    }

    private struct DraftWatch: Equatable {
        var path: String
        var watches: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: InspectorLayout.gap) {
                FilePathLabel(path: path, width: width)
                UnsavedEditsDot(session: session, path: absolutePath)
                Spacer(minLength: InspectorLayout.tight)
                Menu {
                    OpenInAppItems(target: .file(absolutePath))
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                } primaryAction: {
                    Reveal.inEditor(absolutePath, repo: model.repo?.id)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .help("Open in your editor")
                if absolutePathOverride == nil {
                    CanvasOpenButton(model: model, path: path)
                }
                if modes.count > 1 {
                    Picker("File view", selection: Binding(get: { mode }, set: { choose($0) })) {
                        ForEach(modes, id: \.self) { value in
                            Text(value.title(hasPreview: hasPreview)).tag(value)
                        }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                if Language.detect(path: path) == .markdown {
                    MarkdownPreviewButton(isPresented: showsMarkdownPreview) {
                        showsMarkdownPreview.toggle()
                    }
                }
            }
            .controlSize(.small)
            .padding(.horizontal, InspectorLayout.inset)
            .frame(height: InspectorLayout.barHeight)
            .background(Palette.surfaceSunken)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            Hairline()
            if mode == .preview {
                preview
            } else {
                MarkdownPreviewContent(
                    path: absolutePath, revision: model.changesGeneration,
                    isPresented: $showsMarkdownPreview
                ) {
                    FileEditPane(model: model, path: path, session: session, isEditable: mode == .edit,
                                 canEdit: canEditInApp, absolutePathOverride: absolutePathOverride)
                }
                .markdownLinkActions(TranscriptLink.actions(for: model, opensSourceLinks: false))
            }
        }
        .onChange(of: state.prefersEditing) { _, _ in showsMarkdownPreview = false }
        .onChange(of: path, initial: true) { _, path in
            guard Language.detect(path: path) == .markdown, !state.prefersEditing else { return }
            showsMarkdownPreview = true
        }
        .environment(\.openInRepoID, model.repo?.id)
        .onAppear { if session.isDirty(absolutePath) { state.prefersEditing = true } }
        .background {
            Button("Toggle View and Edit") { state.prefersEditing.toggle() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!canEditInApp)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .background {
            Button("Toggle Preview and Source") { choose(mode == .preview ? .source : .preview) }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!hasPreview)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            DocumentPreviewView(
                path: absolutePath,
                worktree: absolutePathOverride == nil ? model.workspace.path : nil,
                revision: model.changesGeneration,
                openFile: { opened in
                    FileReview.openInNewTab(
                        path: DocumentPreview.worktreePath(of: opened, worktree: model.workspace.path),
                        in: model
                    )
                },
                opensLinkInside: { BrowserTab.staysInside($0) },
                openLinkInside: { BrowserTab.open($0, in: model) }
            )
            if controls.showsDiskChange {
                Hairline()
                FileDiskChangeBand(
                    model: model, path: path, absolutePath: absolutePath, session: session,
                    language: state.languageOverride ?? Language.detect(path: path),
                    canOverwrite: controls.canOverwriteDisk
                )
            }
        }
        .focusedValue(\.saveAction, canEditInApp ? SaveAction(subject: absolutePath, isEnabled: controls.canSave, perform: save) : nil)
        .background {
            Button("Save", action: save)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!controls.canSave)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .task(id: DraftWatch(path: absolutePath, watches: controls.watchesDisk)) {
            guard controls.watchesDisk else { return }
            await session.watch(path: absolutePath)
        }
    }

    private func save() {
        Task { _ = await session.save(path: absolutePath, reviewing: path, in: model) }
    }

    private func choose(_ mode: FileTabMode) {
        let preferences = mode.preferences(prefersPreview: state.prefersPreview)
        state.prefersEditing = preferences.prefersEditing
        state.prefersPreview = preferences.prefersPreview
    }
}

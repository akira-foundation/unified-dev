import SwiftUI
import AppKit
import Core

struct FileHeaderBar: View {
    let model: WorkspaceModel
    let file: ChangedFile
    let session: FileEditSession
    var diff: FileDiff?
    @Binding var mode: FileViewMode
    var isEditable: Bool
    var onRevert: () -> Void
    var isCollapsed = false
    var onToggleCollapsed: (() -> Void)?
    var showsMarkdownPreview = false
    var onToggleMarkdownPreview: (() -> Void)?

    @AppStorage(DiffLayoutSetting.storageKey) private var isSideBySide = false
    @AppStorage(DiffWhitespaceSetting.storageKey) private var ignoresWhitespace = false

    @State private var isConfirmingRevert = false
    @State private var didCopy = false
    @State private var copyReset: Task<Void, Never>?
    @State private var hint: String?
    @State private var width: CGFloat = 0

    private var isDirty: Bool { FileRevert.hasUnsavedEdits(at: absolutePath) }

    private var absolutePath: String {
        (model.workspace.path as NSString).appendingPathComponent(file.path)
    }

    var body: some View {
        HStack(spacing: InspectorLayout.gap) {
            if let onToggleCollapsed {
                Button(action: onToggleCollapsed) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 20, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(isCollapsed ? "Expand" : "Collapse") \(file.filename)")
                .accessibilityLabel("\(isCollapsed ? "Expand" : "Collapse") \(file.filename)")
            }
            FilePathLabel(path: file.path, width: width)

            UnsavedEditsDot(session: session, path: absolutePath)

            Spacer(minLength: InspectorLayout.tight)
                .layoutPriority(-1)

            if let onToggleMarkdownPreview {
                MarkdownPreviewButton(isPresented: showsMarkdownPreview, action: onToggleMarkdownPreview)
            }
            if onToggleCollapsed != nil {
                reviewControls
            } else {
                FileBarHintLabel(text: hint ?? "")
                    .layoutPriority(-2)

                ViewThatFits(in: .horizontal) {
                    controls
                    compact
                    collapsed
                }
            }
        }
        .padding(.horizontal, InspectorLayout.inset)
        .frame(height: onToggleCollapsed == nil ? InspectorLayout.barHeight : InspectorLayout.reviewHeaderHeight)
        .background(Palette.surfaceSunken)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .modifier(discardConfirmation)
        .onDisappear { copyReset?.cancel() }
    }

    private var controls: some View {
        HStack(spacing: InspectorLayout.gap) {
            viewedToggle(labelled: true)
            revertButton(labelled: true)
            layoutPicker(labelled: true)
            if mode == .diff {
                whitespaceToggle(labelled: true)
            }
            copyButton(labelled: true)
            modePicker
        }
    }

    private var reviewControls: some View {
        HStack(spacing: InspectorLayout.gap) {
            if !file.isBinary {
                HStack(spacing: 4) {
                    Text("+\(file.additions)").foregroundStyle(Palette.positive)
                    Text("−\(file.deletions)").foregroundStyle(Palette.negative)
                }
                .font(Typo.caption)
                .monospacedDigit()
                .fixedSize()
                .accessibilityLabel("\(file.additions) additions, \(file.deletions) deletions")
            }
            ViewThatFits(in: .horizontal) {
                viewedToggle(labelled: true)
                viewedToggle(labelled: false)
            }
            Menu {
                if isEditable {
                    Button(mode == .diff ? "Edit file" : "Show diff") {
                        if isCollapsed { onToggleCollapsed?() }
                        mode = mode == .diff ? .edit : .diff
                    }
                }
                Button(FileBarControls.copy(mode: mode).title, action: copy)
                Divider()
                RevertMenuItems(entry: FileBarControls.revertMenuEntry(filename: file.filename, blocker: model.revertBlocker)) {
                    isConfirmingRevert = true
                }
            } label: {
                Label("File actions", systemImage: "ellipsis.circle")
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("File actions")
        }
    }

    private var compact: some View {
        HStack(spacing: InspectorLayout.gap) {
            viewedToggle(labelled: false)
            revertButton(labelled: false)
            layoutPicker(labelled: false)
            if mode == .diff {
                whitespaceToggle(labelled: false)
            }
            copyButton(labelled: false)
            modePicker
        }
    }

    private var collapsed: some View {
        HStack(spacing: InspectorLayout.gap) {
            overflowMenu
            modePicker
        }
    }

    private var overflowMenu: some View {
        Menu {
            Toggle("Viewed", isOn: Binding(
                get: { model.isViewed(file) },
                set: { value in Task { await model.setViewed(value, file: file) } }
            ))
            Divider()
            Picker(FileBarControls.layout.title, selection: $isSideBySide) {
                Text(FileBarControls.unified).tag(false)
                Text(FileBarControls.sideBySide).tag(true)
            }
            .pickerStyle(.inline)
            if mode == .diff {
                Toggle(FileBarControls.whitespace(ignoring: ignoresWhitespace).title,
                       isOn: $ignoresWhitespace)
            }
            Divider()
            Button(FileBarControls.copy(mode: mode).title, action: copy)
            RevertMenuItems(entry: FileBarControls.revertMenuEntry(filename: file.filename, blocker: model.revertBlocker)) {
                isConfirmingRevert = true
            }
        } label: {
            Label(FileBarControls.more.title, systemImage: "ellipsis.circle")
        }
        .labelStyle(.iconOnly)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        .fileBarHint(FileBarControls.more, into: $hint)
    }

    private func viewedToggle(labelled: Bool) -> some View {
        ViewedToggle(model: model, file: file)
            .fileBarLabelStyle(labelled: labelled)
            .fileBarHint(FileBarControl(
                title: "Viewed", hint: ReviewedMarkAction(isViewed: model.isViewed(file)).help(for: file.filename)
            ), into: $hint)
    }

    private func revertButton(labelled: Bool) -> some View {
        let control = FileBarControls.revert(filename: file.filename, blocker: model.revertBlocker)
        return Button(role: .destructive) {
            isConfirmingRevert = true
        } label: {
            Label(control.title, systemImage: "arrow.uturn.backward")
        }
        .fileBarLabelStyle(labelled: labelled)
        .inspectorBarControl()
        .disabled(model.revertBlocker != nil)
        .fileBarHint(control, into: $hint)
    }

    private var discardConfirmation: DiscardConfirmation {
        DiscardConfirmation(
            isPresented: $isConfirmingRevert,
            alert: { DiscardAlert.file(file, base: model.workspace.baseBranch, hasDraft: isDirty) },
            onConfirm: onRevert
        )
    }

    private func layoutPicker(labelled: Bool) -> some View {
        Group {
            if labelled {
                Picker(FileBarControls.layout.title, selection: $isSideBySide) {
                    Text(FileBarControls.unified).tag(false)
                    Text(FileBarControls.sideBySide).tag(true)
                }
            } else {
                Picker(FileBarControls.layout.title, selection: $isSideBySide) {
                    Image(systemName: "list.bullet.rectangle")
                        .accessibilityLabel(FileBarControls.unified)
                        .tag(false)
                    Image(systemName: "rectangle.split.2x1")
                        .accessibilityLabel(FileBarControls.sideBySide)
                        .tag(true)
                }
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .disabled(mode == .edit)
        .fileBarHint(FileBarControls.layout, into: $hint)
    }

    private func whitespaceToggle(labelled: Bool) -> some View {
        let control = FileBarControls.whitespace(ignoring: ignoresWhitespace)
        return Toggle(isOn: $ignoresWhitespace) {
            Label(control.title, systemImage: "paragraphsign")
        }
        .fileBarLabelStyle(labelled: labelled)
        .toggleStyle(.button)
        .inspectorBarControl()
        .fileBarHint(control, into: $hint)
    }

    private func copyButton(labelled: Bool) -> some View {
        let control = FileBarControls.copy(mode: mode, didCopy: didCopy)
        return Button(action: copy) {
            Label(control.title, systemImage: didCopy ? "checkmark" : "doc.on.doc")
        }
        .fileBarLabelStyle(labelled: labelled)
        .inspectorBarControl()
        .fileBarHint(control, into: $hint)
    }

    private var modePicker: some View {
        Picker(FileBarControls.mode(filename: file.filename, isEditable: isEditable).title,
               selection: $mode) {
            ForEach(FileViewMode.allCases, id: \.self) { value in
                Text(value.rawValue).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .disabled(!isEditable && mode == .diff)
        .fileBarHint(
            FileBarControls.mode(filename: file.filename, isEditable: isEditable), into: $hint
        )
    }

    private func copy() {
        Task {
            let text: String? = mode == .edit
                ? session.draft(for: absolutePath)?.text
                : await model.patch(for: file)
            guard let text, !text.isEmpty else { return }

            Clipboard.copy(text)

            didCopy = true
            copyReset?.cancel()
            copyReset = Task {
                try? await Task.sleep(for: Clipboard.flashDuration)
                guard !Task.isCancelled else { return }
                didCopy = false
            }
        }
    }
}

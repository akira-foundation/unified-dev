import SwiftUI

struct ComposerEditor: View {
    @Binding var text: String
    @Binding var caret: Int
    @Binding var isFocused: Bool
    var height: CGFloat
    var onContentHeightChange: @MainActor (CGFloat) -> Void
    var onKey: @MainActor (ComposerKey) -> Bool
    var onBackspaceAtStart: @MainActor () -> Bool = { false }
    var onAttach: @MainActor ([AttachmentSource], NSRange) -> Bool
    var onAttachmentFailure: @MainActor @Sendable (String) -> Void = { _ in }
    var attachmentPaths: [String] = []
    var onOpenAttachment: @MainActor (String) -> Void = { _ in }
    var onHoverAttachment: @MainActor (String?) -> Void = { _ in }
    var attachmentRoot: String = ""
    var folderRoot: String?
    var dropOwner: @MainActor () -> String = { "" }
    var handle: ComposerEditorHandle?
    var placeholder: String = ComposerEditor.chatPlaceholder
    var accessibilityLabel: String = "Message"

    static let chatPlaceholder = "Ask to make changes, @mention files, run /commands"

    static let minimumLines = 3

    static let maximumLines = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(Typo.body)
                    .lineLimit(1)
                    .foregroundStyle(Palette.textPlaceholder)
                    .padding(.horizontal, ComposerTextEditor.textInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            ComposerTextEditor(
                text: $text,
                caret: $caret,
                isFocused: $isFocused,
                minLines: Self.minimumLines,
                maxLines: Self.maximumLines,
                accessibilityLabel: accessibilityLabel,
                onHeightChange: onContentHeightChange,
                onKey: onKey,
                onBackspaceAtStart: onBackspaceAtStart,
                onAttach: onAttach,
                onAttachmentFailure: onAttachmentFailure,
                attachmentPaths: attachmentPaths,
                onOpenAttachment: onOpenAttachment,
                onHoverAttachment: onHoverAttachment,
                attachmentRoot: attachmentRoot,
                folderRoot: folderRoot,
                dropOwner: dropOwner,
                handle: handle
            )
            .frame(height: max(height, ComposerTextEditor.lineHeight))
        }
    }
}

import SwiftUI
import AppKit
import Core

enum TranscriptLink {
    static func attributed(_ text: String, tint: Color) -> AttributedString {
        attributed(text, links: LinkScan.links(in: text), tint: tint)
    }

    static func attributed(_ text: String, links: [DetectedLink], tint: Color) -> AttributedString {
        var output = AttributedString()
        var cursor = text.startIndex

        for found in links {
            guard let url = URL(string: found.url), LinkPolicy.opens(url) else { continue }
            if cursor < found.range.lowerBound {
                output += AttributedString(String(text[cursor..<found.range.lowerBound]))
            }
            var span = AttributedString(found.text)
            span.foregroundColor = tint
            span.underlineStyle = .single
            span.link = url
            output += span
            cursor = found.range.upperBound
        }

        if cursor < text.endIndex {
            output += AttributedString(String(text[cursor...]))
        }
        return output
    }

    @MainActor
    static func attributedString(
        sent text: String,
        font: NSFont,
        color: NSColor,
        lineSpacing: CGFloat,
        chipGround: AttachmentChipCell.Ground
    ) -> NSAttributedString {
        let key = SentTurnKey(
            text: text, font: font, color: color, lineSpacing: lineSpacing, ground: chipGround
        )
        if let cached = sentTurns.object(forKey: key) { return cached }

        let value = attributedString(
            SentTurn.segments(in: text),
            font: font,
            color: color,
            lineSpacing: lineSpacing,
            chipGround: chipGround
        )
        sentTurns.setObject(value, forKey: key, cost: text.utf8.count)
        return value
    }

    @MainActor
    private static let sentTurns: NSCache<SentTurnKey, NSAttributedString> = {
        let cache = NSCache<SentTurnKey, NSAttributedString>()
        cache.countLimit = 200
        cache.totalCostLimit = 2 * 1_024 * 1_024
        return cache
    }()

    @MainActor
    static func attributedString(
        _ segments: [SentTurn.Segment],
        font: NSFont,
        color: NSColor,
        lineSpacing: CGFloat,
        chipGround: AttachmentChipCell.Ground
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping

        let output = NSMutableAttributedString()

        for segment in segments {
            switch segment {
            case .text(let words):
                output.append(attributedRun(words, font: font, color: color))
            case .file(let path):
                output.append(
                    ComposerChipText.chip(for: .file(path: path), font: font, ground: chipGround)
                )
            case .instructions(let block):
                output.append(
                    ComposerChipText.chip(
                        for: .instructions(block), font: font, ground: chipGround
                    )
                )
            }
        }

        addSourceIcons(to: output)

        output.addAttribute(
            .paragraphStyle, value: paragraph, range: NSRange(location: 0, length: output.length)
        )
        return output
    }

    @MainActor
    private static func attributedRun(
        _ text: String, font: NSFont, color: NSColor
    ) -> NSAttributedString {
        let run = NSMutableAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: color]
        )
        for found in LinkScan.links(in: text) {
            guard let url = URL(string: found.url), LinkPolicy.opens(url) else { continue }
            run.addAttribute(.link, value: url, range: NSRange(found.range, in: text))
        }
        for (range, url) in SourceReference.links(in: text)
            where run.attribute(.link, at: range.location, effectiveRange: nil) == nil {
            run.addAttribute(.link, value: url, range: range)
        }
        return run
    }

    @MainActor
    static func addSourceIcons(to text: NSMutableAttributedString) {
        var links: [(NSRange, CodeLocation)] = []
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let url = value as? URL, let location = SourceReference.location(url) else { return }
            links.append((range, location))
        }
        for (range, location) in links.reversed() {
            let attributes = text.attributes(at: range.location, effectiveRange: nil)
            let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: NSFont.systemFontSize)
            let size = ceil(font.pointSize)
            let attachment = NSTextAttachment()
            attachment.image = FileTypeIcon.icon(for: location.path)
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - size) / 2, width: size, height: size)
            let icon = NSMutableAttributedString(attachment: attachment)
            icon.addAttributes(attributes, range: NSRange(location: 0, length: icon.length))
            text.insert(icon, at: range.location)
        }
    }

    @MainActor
    static func selectedText(in storage: NSAttributedString, range: NSRange) -> String {
        let selection = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        var icons: [NSRange] = []
        selection.enumerateAttribute(.attachment, in: NSRange(location: 0, length: selection.length)) { value, range, _ in
            guard value is NSTextAttachment,
                  let url = selection.attribute(.link, at: range.location, effectiveRange: nil) as? URL,
                  SourceReference.location(url) != nil else { return }
            icons.append(range)
        }
        for range in icons.reversed() { selection.deleteCharacters(in: range) }
        return ComposerChipText.draft(of: selection)
    }

    @MainActor
    static func actions(
        for model: WorkspaceModel?, pane: String? = nil, session: SessionID? = nil, opensSourceLinks: Bool = true
    ) -> TranscriptLinkActions {
        TranscriptLinkActions(
            identity: .workspace(model?.workspace.id, pane: pane, session: session),
            open: { url, target in
                if opensSourceLinks, let location = SourceReference.location(url), let model {
                    FileReview.open(location: location, in: model)
                    return
                }
                switch target {
                case .externalBrowser:
                    guard LinkPolicy.opens(url) else { return }
                    NSWorkspace.shared.open(url)
                case .browserTab:
                    guard let model else { return }
                    BrowserTab.open(url, in: model)
                case .split(let axis):
                    guard let model, let pane else { return }
                    BrowserTab.split(url, in: model, pane: pane, axis: axis)
                }
            },
            clickTarget: { url in
                LinkOpening.target(
                    for: url, placement: BrowserTab.placement(of: pane, in: model),
                    isEnabled: BrowserTab.opensLinksInside
                )
            },
            items: { url in
                TranscriptLinkMenu.items(
                    for: url, placement: BrowserTab.placement(of: pane, in: model)
                )
            },
            previewSource: { url in
                guard opensSourceLinks, let location = SourceReference.location(url), let model else { return nil }
                let target = FileChipTarget.resolve(
                    FileReview.linked(location.path, in: model).path(trackedInCheckout: false), in: model.workspace.path
                )
                return PromptAttachment.sent(path: target.path).url(in: target.worktree)
            },
            runCommand: runCommand(in: model, session: session),
            stopCommand: { command in
                guard let session else { return }
                CodeBlockRunStore.shared.stop(command, in: session)
            },
            commandRun: { command in
                guard let session else { return nil }
                return CodeBlockRunStore.shared.state(of: command, in: session)
            }
        )
    }

    @MainActor
    private static func runCommand(
        in model: WorkspaceModel?, session: SessionID?
    ) -> (@MainActor @Sendable (String) -> Void)? {
        guard let model, let session, CodeBlockRunStore.shared.canRun(in: session, of: model) else { return nil }
        return { command in CodeBlockRunStore.shared.run(command, in: session, of: model) }
    }

    static func copy(_ url: String) {
        Clipboard.copy(url)
    }
}

private final class SentTurnKey: NSObject {
    let text: String
    let font: NSFont
    let color: NSColor
    let lineSpacing: CGFloat
    let ground: AttachmentChipCell.Ground
    private let cachedHash: Int

    init(text: String, font: NSFont, color: NSColor, lineSpacing: CGFloat, ground: AttachmentChipCell.Ground) {
        self.text = text
        self.font = font
        self.color = color
        self.lineSpacing = lineSpacing
        self.ground = ground
        var hasher = Hasher()
        hasher.combine(text)
        hasher.combine(font)
        hasher.combine(color)
        hasher.combine(lineSpacing)
        hasher.combine(ground.plate)
        cachedHash = hasher.finalize()
    }

    override var hash: Int { cachedHash }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SentTurnKey else { return false }
        return cachedHash == other.cachedHash
            && text == other.text
            && font == other.font
            && color == other.color
            && lineSpacing == other.lineSpacing
            && ground == other.ground
    }
}

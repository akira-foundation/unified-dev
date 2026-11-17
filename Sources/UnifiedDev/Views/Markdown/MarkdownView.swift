import SwiftUI
import AppKit
import Core

private final class MarkdownBlockBox: NSObject {
    let blocks: [MarkdownBlock]

    let addresses: [String]

    init(_ blocks: [MarkdownBlock], addresses: [String]) {
        self.blocks = blocks
        self.addresses = addresses
    }

    convenience init(_ blocks: [MarkdownBlock]) {
        self.init(blocks, addresses: LinkPolicy.addresses(in: blocks))
    }
}

private enum MarkdownParseCache {
    nonisolated(unsafe) static let values: NSCache<NSString, MarkdownBlockBox> = {
        let cache = NSCache<NSString, MarkdownBlockBox>()
        cache.countLimit = 0
        cache.totalCostLimit = 8 * 1_024 * 1_024
        return cache
    }()

    static func parsed(for text: String) -> MarkdownBlockBox {
        let key = text as NSString
        if let cached = values.object(forKey: key) { return cached }
        let box = MarkdownBlockBox(MarkdownParser.parse(text))
        values.setObject(box, forKey: key, cost: text.utf8.count)
        return box
    }
}

enum MarkdownPrime {
    static func blocks(of text: String) -> [MarkdownBlock] {
        MarkdownParseCache.parsed(for: text).blocks
    }
}

public struct MarkdownView: View {
    private let text: String
    private let isStreaming: Bool

    @State private var expanded: Set<Int> = []
    @State private var footers: [Int: CGFloat] = [:]
    @State private var streamSlot = MarkdownStreamSlot()

    @Environment(\.fontScale) private var fontScale
    @Environment(\.chatFont) private var chatFont
    @Environment(\.chatLineHeight) private var chatLineHeight
    @Environment(\.lineSpacing) private var ambientLeading
    @Environment(\.markdownLinkActions) private var linkActions
    @Environment(\.markdownRunsCommands) private var runsCommands

    public init(_ text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    private var parsed: (blocks: [MarkdownBlock], addresses: [String]) {
        guard isStreaming else {
            streamSlot.forgetStream()
            let box = MarkdownParseCache.parsed(for: text)
            return (box.blocks, box.addresses)
        }
        return (streamSlot.blocks(streaming: text), [])
    }

    public var body: some View {
        let parsed = self.parsed
        let style = MarkdownTextStyle(
            scale: fontScale, face: chatFont, lineHeight: chatLineHeight, ambientLeading: ambientLeading
        )
        MarkdownTextView(
            content: MarkdownTextCache.text(
                for: MarkdownTextKey(text: text, isStreaming: isStreaming, style: style, expanded: expanded, footers: footers),
                blocks: parsed.blocks,
                slot: streamSlot
            ),
            actions: linkActions,
            runsCommands: runsCommands && !isStreaming,
            fontScale: fontScale,
            chatFont: chatFont,
            onToggleFold: { index in
                if expanded.remove(index) == nil { expanded.insert(index) }
            },
            onFooterHeight: { index, height in
                if footers[index] == nil, height < 0.5 { return }
                if abs((footers[index] ?? 0) - height) > 0.5 { footers[index] = height }
            }
        )
        .transcriptLinkMenu(parsed.addresses)
        .transcriptLinkActions(parsed.addresses)
    }
}

extension View {
    func markdownLinkActions(_ actions: TranscriptLinkActions) -> some View {
        environment(\.markdownLinkActions, actions)
    }
}

extension EnvironmentValues {
    @Entry var markdownRunsCommands: Bool = false
    @Entry var markdownLinkActions = TranscriptLinkActions()
}

@MainActor
enum InlineNSAttributes {
    static func rendered(
        _ inline: [MarkdownInline],
        font: NSFont,
        code: NSFont,
        color: NSColor,
        addsSourceIcons: Bool
    ) -> NSMutableAttributedString {
        let output = NSMutableAttributedString()
        render(inline, font: font, code: code, color: color, traits: [], into: output)
        if addsSourceIcons { TranscriptLink.addSourceIcons(to: output) }
        return output
    }

    private static func render(
        _ values: [MarkdownInline],
        font: NSFont,
        code: NSFont,
        color: NSColor,
        traits: NSFontTraitMask,
        into output: NSMutableAttributedString
    ) {
        for value in values {
            switch value {
            case let .text(text):
                let child = run(text, font: faced(font, traits), color: color)
                for (range, url) in SourceReference.links(in: text) { child.addAttribute(.link, value: url, range: range) }
                output.append(child)
            case let .emphasis(children):
                render(children, font: font, code: code, color: color, traits: traits.union(.italicFontMask), into: output)
            case let .strong(children):
                render(children, font: font, code: code, color: color, traits: traits.union(.boldFontMask), into: output)
            case let .strikethrough(children):
                let start = output.length
                render(children, font: font, code: code, color: color, traits: traits, into: output)
                output.addAttribute(
                    .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                    range: NSRange(location: start, length: output.length - start)
                )
            case let .code(text):
                let child = run(text, font: faced(code, traits), color: color)
                child.addAttribute(
                    .backgroundColor, value: Palette.hoverNSColor,
                    range: NSRange(location: 0, length: child.length)
                )
                if let target = SourceReference.url(text) {
                    child.addAttribute(.link, value: target, range: NSRange(location: 0, length: child.length))
                }
                output.append(child)
            case let .link(text, url):
                let start = output.length
                render(text, font: font, code: code, color: color, traits: traits, into: output)
                if let target = LinkPolicy.target(of: url) {
                    output.addAttribute(
                        .link, value: target,
                        range: NSRange(location: start, length: output.length - start)
                    )
                }
            case .lineBreak:
                output.append(run("\n", font: faced(font, traits), color: color))
            }
        }
    }

    private static func run(_ text: String, font: NSFont, color: NSColor) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    private static func faced(_ font: NSFont, _ traits: NSFontTraitMask) -> NSFont {
        guard !traits.isEmpty else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: traits)
    }
}

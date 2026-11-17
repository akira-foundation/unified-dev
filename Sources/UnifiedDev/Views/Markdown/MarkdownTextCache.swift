import AppKit
import Core

struct MarkdownTextKey: Hashable {
    var text: String
    var isStreaming: Bool
    var style: MarkdownTextStyle
    var expanded: Set<Int>
    var footers: [Int: CGFloat]
}

private final class MarkdownTextKeyBox: NSObject {
    let key: MarkdownTextKey

    init(_ key: MarkdownTextKey) { self.key = key }

    override var hash: Int { key.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? MarkdownTextKeyBox)?.key == key
    }
}

@MainActor
final class MarkdownStreamSlot {
    static var probeTap: ((String, [MarkdownBlock], Double) -> Void)?

    var key: MarkdownTextKey?
    var text: MarkdownText?
    private var parse = MarkdownStreamParse()
    private var parsed: (text: String, blocks: [MarkdownBlock])?

    func blocks(streaming text: String) -> [MarkdownBlock] {
        if let parsed, parsed.text == text { return parsed.blocks }
        let started = ProcessInfo.processInfo.systemUptime
        let blocks = parse.blocks(for: text)
        parsed = (text, blocks)
        Self.probeTap?(text, blocks, ProcessInfo.processInfo.systemUptime - started)
        return blocks
    }

    func forgetStream() {
        guard parsed != nil else { return }
        parse = MarkdownStreamParse()
        parsed = nil
    }
}

@MainActor
enum MarkdownTextCache {
    private static let values: NSCache<MarkdownTextKeyBox, MarkdownText> = {
        let cache = NSCache<MarkdownTextKeyBox, MarkdownText>()
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    static func text(for key: MarkdownTextKey, blocks: [MarkdownBlock], slot: MarkdownStreamSlot) -> MarkdownText {
        var builder = MarkdownTextBuilder(
            style: key.style, isStreaming: key.isStreaming, expanded: key.expanded, footers: key.footers
        )
        guard key.isStreaming else {
            let box = MarkdownTextKeyBox(key)
            if let held = values.object(forKey: box) { return held }
            let text = builder.build(blocks, continuing: nil)
            values.setObject(text, forKey: box, cost: key.text.utf8.count * 8)
            return text
        }
        if let held = slot.key, held == key, let text = slot.text { return text }
        var reusable: MarkdownText?
        if let held = slot.key, held.style == key.style, held.footers == key.footers, held.expanded == key.expanded {
            reusable = slot.text
        }
        let text = builder.build(blocks, continuing: reusable)
        slot.key = key
        slot.text = text
        return text
    }
}

import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum SelectionReplyProbe {
    private static let harness = ProbeHarness(subject: "selection-reply")
    static var isRequested: Bool { harness.isRequested }
    static func schedule() { Task { @MainActor in await run() } }

    @MainActor
    private final class Log {
        var ran: [String] = []
        var replied: [String] = []
    }

    private final class FocusedWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var isKeyWindow: Bool { true }
    }

    private static func click(_ point: NSPoint, in window: NSWindow) async {
        NSApp.postEvent(MarkdownSelectionProbe.mouseEvent(.leftMouseUp, at: point, in: window), atStart: false)
        NSApp.sendEvent(MarkdownSelectionProbe.mouseEvent(.leftMouseDown, at: point, in: window))
        NSApp.sendEvent(MarkdownSelectionProbe.mouseEvent(.leftMouseUp, at: point, in: window))
        try? await Task.sleep(for: .milliseconds(300))
    }

    private static func pressOnText(at point: NSPoint, reader: TranscriptSelectionReader, in window: NSWindow) async {
        _ = reader.handle(MarkdownSelectionProbe.mouseEvent(.leftMouseDown, at: point, in: window))
        try? await Task.sleep(for: .milliseconds(300))
    }

    private static func key(_ character: String, _ code: UInt16, in window: NSWindow) async {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            NSApp.sendEvent(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: code
            )!)
        }
        try? await Task.sleep(for: .milliseconds(200))
    }

    private static let topInset: CGFloat = 52

    private static func run() async {
        for _ in 0..<120 where ProbeHarness.appModel == nil { try? await Task.sleep(for: .milliseconds(250)) }
        guard let app = ProbeHarness.appModel else { harness.fail("no app model") }
        var failures: [String] = []
        func check(_ passed: Bool, _ message: String) {
            if !passed { failures.append(message) }
        }
        let window = FocusedWindow(contentRect: NSRect(x: -6000, y: -6000, width: 640, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        let log = Log()
        let actions = TranscriptLinkActions(identity: .workspace(nil, pane: "probe", session: nil), runCommand: { log.ran.append($0) })
        let controller = TranscriptTableController()
        let reader = TranscriptSelectionReader()
        reader.accepts = { _ in true }
        let text = "An answer worth quoting, long enough to drag across.\n\n```bash\nls -la\n```\n\nThe last line."
        let entries = [TranscriptTableEntry(
            id: .row(1), contentKey: TranscriptContentKey { $0.combine("answer") }, shape: .answer,
            content: { AnyView(MarkdownView(text).environment(\.markdownRunsCommands, true).proseLeading().padding(8)) }
        ), .bottomSpacing]
        let table = TranscriptTable(
            entries: entries, session: SessionID("reply-probe"), controller: controller,
            scale: ChatTextSize.defaultChoice.scale,
            rowEnvironment: TranscriptRowEnvironment(
                app: app, hoverHost: TranscriptHoverHost(), bubbleWidth: TranscriptBubbleWidth(),
                linkActions: actions, fontScale: ChatTextSize.defaultChoice.scale,
                chatFont: .standard, lineHeight: .defaultChoice, reduceMotion: true
            ),
            onGeometryChange: { _ in }, onSettled: {}, onLiveScrollChange: { _ in }
        )
        let overlay = SelectionActionOverlay(reader: reader, onSideChat: nil, agent: "Claude Code", onReply: { log.replied.append("\($0.text)|\($1)") })
        let host = NSHostingView(rootView: AnyView(
            table.ignoresSafeArea(.container, edges: .top)
                .overlay { overlay }
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: topInset) }
        ))
        window.contentView = host
        for _ in 0..<16 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(150))
        }
        reader.start(controller: controller)
        guard let view = MarkdownSelectionProbe.textViews(in: host).first, let header = view.markdown?.chromeViews.first else { harness.fail("no answer") }
        func place(_ index: Int) -> NSPoint { view.convert(MarkdownSelectionProbe.point(of: index, in: view), to: nil) }
        func inWindow(_ point: CGPoint) -> NSPoint { host.convert(NSPoint(x: point.x, y: point.y + topInset), to: nil) }

        let runPoint = NSPoint(
            x: header.frame.maxX - MarkdownMetrics.blockGap - MarkdownMetrics.iconButton * 1.5 - Metrics.spacing,
            y: header.frame.minY + Metrics.spacing + MarkdownMetrics.iconButton / 2
        )
        await click(view.convert(runPoint, to: nil), in: window)
        check(log.ran == ["ls -la"], "Run in a transcript row ran \(log.ran)")

        let from = place(0)
        let to = place(20)
        reader.pointerLocation = { _ in to }
        window.makeFirstResponder(view)
        NSApp.postEvent(MarkdownSelectionProbe.mouseEvent(.leftMouseDragged, at: to, in: window), atStart: false)
        NSApp.postEvent(MarkdownSelectionProbe.mouseEvent(.leftMouseUp, at: to, in: window), atStart: false)
        view.mouseDown(with: MarkdownSelectionProbe.mouseEvent(.leftMouseDown, at: from, in: window))
        await pressOnText(at: from, reader: reader, in: window)
        guard reader.current != nil else { harness.fail("the drag raised no selection bar") }
        check(!reader.barFrame.isNull && reader.barFrame.width < 200 && reader.barFrame.height < 80, "the bar claims \(reader.barFrame), so a press beside it reads as a press on it")

        view.setSelectedRange(NSRange(location: 3, length: 6))
        await pressOnText(at: from, reader: reader, in: window)
        check(reader.current?.text == "answer", "a press beside the bar left it quoting \(String(describing: reader.current?.text))")

        await click(view.convert(runPoint, to: nil), in: window)
        check(reader.current == nil, "a press on Run raised the bar over the selection")
        check(log.ran == ["ls -la", "ls -la"], "Run under a selection ran \(log.ran)")

        await pressOnText(at: from, reader: reader, in: window)
        guard reader.current != nil else { harness.fail("the selection did not raise the bar again") }
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(120))
        }
        await click(inWindow(CGPoint(x: reader.barFrame.midX, y: reader.barFrame.midY)), in: window)
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(120))
        }
        guard reader.replying != nil else { harness.fail("a click on Reply did not open the card") }
        check(window.firstResponder !== view, "the transcript kept the keyboard after Reply")
        check((window.firstResponder as? NSTextView)?.delegate is NSTextField, "the reply field did not take the keyboard when the card opened: \(String(describing: window.firstResponder))")
        await key("a", 0, in: window)
        check((window.firstResponder as? NSTextView)?.string == "a", "typing without a click did not reach the reply field: \(String(describing: window.firstResponder))")
        await click(inWindow(CGPoint(x: reader.replyFrame.minX + 40, y: reader.replyFrame.maxY - 24)), in: window)
        check(reader.replying != nil, "a click in the reply field closed the card")
        await key("\r", 36, in: window)
        check(log.replied == ["answer|a"], "Return replied with \(log.replied)")
        check(reader.replying == nil, "the card stayed open after Return")

        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 3, length: 6))
        await pressOnText(at: from, reader: reader, in: window)
        guard let again = reader.current else { harness.fail("the selection did not raise the bar a third time") }
        reader.beginReply(to: again)
        check(window.firstResponder !== view, "the transcript still held the keyboard when the card was asked for, so the card's focus request races it")
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(120))
        }
        check((window.firstResponder as? NSTextView)?.delegate is NSTextField, "the reopened card did not take the keyboard")
        await key("\u{1b}", 53, in: window)
        check(reader.replying == nil, "Escape did not close the card")
        check(log.replied == ["answer|a"], "Escape replied with \(log.replied)")

        harness.write(.object(["passed": .bool(failures.isEmpty), "failures": .array(failures.map(JSONValue.string))]))
        exit(failures.isEmpty ? 0 : 1)
    }
}
#endif

import AppKit
import Core

@MainActor
enum MessageContextMenu {
    static func present(
        for row: TranscriptRow,
        selection: String?,
        transcript: TranscriptModel,
        onFork: ((Int) -> Void)?,
        event: NSEvent,
        in view: NSView
    ) {
        let menu = ActionMenu()
        menu.autoenablesItems = false
        let markdown = MessageCopyText.markdown(kind: row.kind, payload: row.payload)
        let plain = MessageCopyText.plain(kind: row.kind, payload: row.payload)
        let context = MessageMenuContext(
            hasSelection: selection != nil, hasText: plain != nil,
            isChapter: transcript.isChapter(row.seq), canFork: onFork != nil
        )

        for (index, section) in MessageMenu.sections(for: context).enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for item in section {
                menu.add(item) {
                    switch item.action {
                    case .copy: NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    case .copyMessage: plain.map(Clipboard.copy)
                    case .copyMessageAsMarkdown: markdown.map(Clipboard.copy)
                    case .attachSelection: if let selection { transcript.reply(with: selection, from: row.seq) }
                    case .pinChapter: transcript.pinChapter(row)
                    case .unpinChapter: transcript.unpinChapter(seq: row.seq)
                    case .forkFromHere: onFork?(row.seq)
                    }
                }
            }
        }

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

@MainActor
private final class ActionMenu: NSMenu {
    private var actions: [ActionItem] = []

    init() { super.init(title: "") }

    required init(coder: NSCoder) {
        fatalError("ActionMenu is only ever built in code")
    }

    func add(_ entry: MessageMenuItem, perform: @escaping @MainActor () -> Void) {
        let action = ActionItem(perform: perform)
        actions.append(action)
        let item = NSMenuItem(
            title: entry.action.title, action: #selector(ActionItem.fire), keyEquivalent: entry.action.keyEquivalent
        )
        item.keyEquivalentModifierMask = entry.action.needsShift ? [.command, .shift] : .command
        item.target = action
        item.isEnabled = entry.isEnabled
        addItem(item)
    }
}

@MainActor
private final class ActionItem: NSObject {
    private let perform: @MainActor () -> Void

    init(perform: @escaping @MainActor () -> Void) { self.perform = perform }

    @objc func fire() { perform() }
}

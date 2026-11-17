import AppKit
import SwiftUI
import Core

@MainActor
final class MenuBarStatusItem: NSObject {
    static let shared = MenuBarStatusItem()

    static let settingKey = "menuBar.showsStatusItem"

    static let isOnByDefault = true

    private var item: NSStatusItem?
    private weak var app: AppModel?
    private var unreadCount = 0
    private var waitingCount = 0
    private var keepsAwake = false
    private var strip = MenuBarUsageStrip()
    private let model = UsageMenuModel.shared
    private let panel = MenuBarPanelPresenter()

    private override init() {}

    func setEnabled(_ isEnabled: Bool, app: AppModel) {
        self.app = app
        app.isMenuBarPanelOpen = { [weak self] in self?.panel.isOpen ?? false }
        model.refresh = { [weak app] in
            guard let app else { return }
            Task { await app.refreshQuotas(after: 0) }
        }

        guard isEnabled else {
            panel.close()
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        guard item == nil else { return }

        let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        created.button?.imagePosition = .imageLeading
        created.button?.target = self
        created.button?.action = #selector(togglePanel)
        _ = created.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        item = created
        observeUsage()
        refreshButton()
        claimPlaceInMenuBar(created)
    }

    private func claimPlaceInMenuBar(_ item: NSStatusItem, attemptsLeft: Int = 3) {
        guard attemptsLeft > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard self.item === item, Self.isParked(item) else { return }
            item.isVisible = false
            item.isVisible = true
            claimPlaceInMenuBar(item, attemptsLeft: attemptsLeft - 1)
        }
    }

    private static func isParked(_ item: NSStatusItem) -> Bool {
        guard let window = item.button?.window else { return false }
        guard let screen = window.screen ?? NSScreen.main else { return false }
        return window.frame.maxX >= screen.frame.maxX
    }

    func setUnreadCount(_ count: Int) {
        guard count != unreadCount else { return }
        unreadCount = count
        refreshButton()
    }

    func setWaitingCount(_ count: Int) {
        guard count != waitingCount else { return }
        waitingCount = count
        refreshButton()
    }

    func setKeepsAwake(_ isOn: Bool) {
        guard isOn != keepsAwake else { return }
        keepsAwake = isOn
        refreshButton()
    }

    private func observeUsage() {
        guard let app, item != nil else { return }
        let metrics = withObservationTracking {
            _ = model.layout
            _ = model.options
            _ = model.iconStyle
            _ = model.showsUsage
            _ = model.showsWaitingCount
            _ = model.showsUnreadCount
            return UsageCatalogue.metrics(quotas: app.quotas, accounts: app.accounts)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeUsage() }
        }
        model.adopt(metrics)
        strip = model.showsUsage
            ? MenuBarUsageStrip.make(layout: model.layout, metrics: metrics, options: model.options)
            : MenuBarUsageStrip()
        refreshButton()
    }

    private func refreshButton() {
        guard let button = item?.button else { return }
        if !strip.isEmpty, let image = MenuBarStripImage.image(for: strip, style: model.iconStyle) {
            button.image = image
        } else {
            button.image = AppMenuBarMark.image
        }

        let segments = MenuBarSummary.segments(
            waiting: waitingCount,
            unread: unreadCount,
            showsWaiting: model.showsWaitingCount,
            showsUnread: model.showsUnreadCount
        )
        let showsCup = keepsAwake && model.showsCup
        button.attributedTitle = Self.title(for: segments, keepsAwake: showsCup, font: button.font)

        var spoken = [MenuBarSummary.tooltip(waiting: waitingCount, unread: unreadCount)]
        if showsCup { spoken.insert(KeepAwake.onHeadline, at: 0) }
        if !strip.isEmpty { spoken.insert(strip.spoken, at: 0) }
        button.toolTip = spoken.joined(separator: "\n")
        button.setAccessibilityLabel("Unified Dev. " + spoken.joined(separator: ". "))
    }

    private static let leadingGap: CGFloat = 4
    private static let betweenGap: CGFloat = 7

    private static func title(
        for segments: [MenuBarSummary.Segment],
        keepsAwake: Bool,
        font: NSFont?
    ) -> NSAttributedString {
        let title = NSMutableAttributedString()
        let font = font ?? NSFont.menuBarFont(ofSize: 0)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        var isFirst = true
        func gap() {
            title.append(NSAttributedString(
                string: " ",
                attributes: [.font: font, .kern: isFirst ? leadingGap : betweenGap]
            ))
            isFirst = false
        }

        if keepsAwake, let cup = glyph(named: KeepAwake.menuBarSymbol, label: KeepAwake.onHeadline, font: font) {
            gap()
            title.append(cup)
        }
        for segment in segments {
            gap()
            if let glyph = glyph(named: segment.symbolName, label: segment.label, font: font) {
                title.append(glyph)
                title.append(NSAttributedString(string: " ", attributes: attributes))
            }
            title.append(NSAttributedString(string: String(segment.count), attributes: attributes))
        }
        return title
    }

    private static func glyph(named name: String, label: String, font: NSFont) -> NSAttributedString? {
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize * 0.72, weight: .semibold)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(configuration) else { return nil }
        image.isTemplate = true

        let attachment = NSTextAttachment()
        attachment.image = image
        let size = image.size
        attachment.bounds = CGRect(x: 0, y: font.descender * 0.5, width: size.width, height: size.height)
        return NSAttributedString(attachment: attachment)
    }

    @objc private func togglePanel() {
        guard let app, let button = item?.button else { return }
        panel.toggle(app: app, model: model, below: button)
    }
}

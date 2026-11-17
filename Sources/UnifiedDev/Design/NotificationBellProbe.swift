import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum NotificationBellProbe {
    private static let flag = "--notification-bell-probe"

    static var isRequested: Bool { CommandLine.arguments.contains(flag) }

    static func runAndExit() -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { await run() }
        RunLoop.main.run()
        exit(1)
    }

    private static var directory: String {
        ProbeHarness.text(flag, or: NSTemporaryDirectory() + "unifieddev-notification-bell")
    }

    private static let unified = Profile(
        id: .initial, name: "Unified", folder: "unified", colour: Accent.all[0], symbol: "square.stack.3d.up"
    )
    private static let akira = Profile(
        id: ProfileID("akira"), name: "Akira", folder: "akira", colour: "4C8DF6", symbol: "building.2"
    )
    private static let debtges = Profile(
        id: ProfileID("debtges"), name: "Debtges", folder: "debtges", colour: "E06C2A", symbol: "briefcase"
    )
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func row(
        _ event: NotificationEvent,
        _ name: String,
        _ detail: String,
        minutes: Double,
        profile: Profile?,
        read: Bool = false,
        state: WorkspaceState? = .active
    ) -> InboxNotification {
        InboxNotification(
            event: event,
            workspaceID: WorkspaceID(name),
            sessionID: SessionID(name),
            workspaceName: name,
            detail: detail,
            createdAt: now.addingTimeInterval(-minutes * 60),
            readAt: read ? now : nil,
            profileID: profile?.id,
            workspaceState: state
        )
    }

    private static let rows = [
        row(.needsInput, "Quarterly close", "Wants to run git push origin main.", minutes: 2, profile: akira),
        row(.turnFinished, "Reminder letters", "The letters now use the new template.", minutes: 9, profile: debtges),
        row(.quotaExhausted, "Payment plans", "All of the 5 hours allowance used", minutes: 21, profile: debtges),
        row(.checksFinished, "Tide tables", "3 of 3 checks passed", minutes: 64, profile: unified, read: true),
        row(.agentFailed, "Old statements", "The agent exited without finishing.", minutes: 180, profile: debtges, state: .archived),
        row(.setupFailed, "Removed work", "", minutes: 900, profile: nil, state: nil),
    ]

    private static func run() async {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var written = 0
        for scheme in [ColorScheme.light, .dark] {
            if await shoot("list", rows: rows, scheme: scheme) { written += 1 }
            if await shoot("empty", rows: [], scheme: scheme) { written += 1 }
            if await shoot("long", rows: longRows, scheme: scheme) { written += 1 }
            if await shoot("all-read", rows: rows.map(\.asRead), scheme: scheme) { written += 1 }
        }
        exit(written == 8 ? 0 : 1)
    }

    private static var longRows: [InboxNotification] {
        (0..<4).flatMap { round in
            rows.map { row in
                var copy = row
                copy.id = InboxNotificationID("\(row.id.rawValue)-\(round)")
                return copy
            }
        }
    }

    private static func shoot(_ name: String, rows: [InboxNotification], scheme: ColorScheme) async -> Bool {
        let view = NotificationBellList(
            rows: rows, profiles: [unified, akira, debtges], now: now, onOpen: { _ in }, onMarkAll: {}
        )
        let host = NSHostingController(rootView: view
            .environment(\.colorScheme, scheme)
            .background(Palette.surface)
            .transaction { $0.disablesAnimations = true })
        host.sizingOptions = []
        let tall = CGSize(width: NotificationBellReading.popoverWidth, height: 1_200)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: tall), styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentViewController = host
        host.view.frame = CGRect(origin: .zero, size: tall)
        host.view.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))
        let size = host.sizeThatFits(in: tall)
        report("\(name)-\(scheme): \(Int(size.width))x\(Int(size.height))")
        window.setContentSize(size)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))
        host.view.displayIfNeeded()
        guard let bitmap = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else { return false }
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(filePath: "\(directory)/\(name)-\(scheme).png"))) != nil
    }

    private static func report(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

private extension InboxNotification {
    var asRead: InboxNotification {
        var copy = self
        copy.readAt = copy.readAt ?? copy.createdAt
        return copy
    }
}

#endif

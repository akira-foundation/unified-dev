import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum DiscardAlertProbe {
    private static let flag = "--discard-alert-probe"

    static var isRequested: Bool { CommandLine.arguments.contains(flag) }

    static func runAndExit() -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.finishLaunching()
        Task { await run() }
        RunLoop.main.run()
        exit(1)
    }

    private static var directory: String {
        ProbeHarness.text(flag, or: NSTemporaryDirectory() + "unifieddev-discard-alert")
    }

    private static func run() async {
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("\(directory): \(error)\n".utf8))
            exit(1)
        }
        var failures: [String] = []
        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        for (name, alert) in scenes {
            for (scheme, appearance) in appearances {
                failures += await shoot(alert, named: "\(name)-\(scheme)", appearance: appearance)
            }
        }
        for failure in failures {
            FileHandle.standardError.write(Data((failure + "\n").utf8))
        }
        let total = scenes.count * appearances.count
        FileHandle.standardError.write(Data("photographed \(total), \(failures.count) complaints\n".utf8))
        exit(failures.isEmpty ? 0 : 1)
    }

    private static func shoot(_ alert: DiscardAlert, named name: String, appearance: NSAppearance.Name) async -> [String] {
        NSApplication.shared.appearance = NSAppearance(named: appearance)
        let host = NSHostingController(rootView: Color.clear
            .frame(width: 520, height: 360)
            .discardConfirmation(isPresented: .constant(true), alert: { alert }, onConfirm: {}))
        let window = NSWindow(contentViewController: host)
        window.setFrameOrigin(NSPoint(x: -9_000, y: -9_000))
        window.orderFront(nil)
        defer { window.close() }

        var sheet: NSWindow?
        for _ in 0..<60 where sheet == nil {
            try? await Task.sleep(for: .milliseconds(50))
            sheet = window.attachedSheet
        }
        guard let sheet else { return ["\(name): no alert was presented"] }
        defer { window.endSheet(sheet) }
        sheet.displayIfNeeded()

        var failures = keys(in: sheet, against: alert, named: name)
        guard let view = sheet.contentView, let layer = view.layer,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return failures + ["\(name): nothing to draw into"]
        }
        NSGraphicsContext.current = context
        sheet.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            view.bounds.fill()
        }
        NSGraphicsContext.current = nil
        if view.isFlipped {
            context.cgContext.translateBy(x: 0, y: view.bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context.cgContext)
        context.flushGraphics()
        guard let drawn = bitmap.representation(using: .png, properties: [:]) else {
            return failures + ["\(name): the drawing is not a png"]
        }
        do {
            try drawn.write(to: URL(filePath: directory + "/" + name + ".png"))
        } catch {
            failures.append("\(name): \(error)")
        }
        return failures
    }

    private static func keys(in sheet: NSWindow, against alert: DiscardAlert, named name: String) -> [String] {
        let buttons = sheet.contentView.map(buttons(in:)) ?? []
        let titles = Set(buttons.map(\.title))
        var failures: [String] = []
        if titles != Set(alert.actions.map(\.label)) {
            failures.append("\(name): the alert carries \(titles.sorted()), Core asks for \(alert.actions.map(\.label))")
        }
        let returning = buttons.filter { $0.keyEquivalent == "\r" }.map(\.title)
        let escaping = buttons.filter { $0.keyEquivalent == "\u{1b}" }.map(\.title)
        let returns = alert.returnKey.map { [$0.label] } ?? []
        let cancelling = alert.actions.filter { $0.role == .cancel && $0 != alert.returnKey }.map(\.label)
        if returning != returns {
            failures.append("\(name): return hits \(returning), not \(returns)")
        }
        if !cancelling.isEmpty, escaping != cancelling {
            failures.append("\(name): escape hits \(escaping), not \(cancelling)")
        }
        FileHandle.standardError.write(Data("\(name): return \(returning), escape \(escaping)\n".utf8))
        return failures
    }

    private static func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons(in:))
    }

    private static let hunk = DiffHunk(oldStart: 12, oldCount: 3, newStart: 12, newCount: 4, lines: [
        DiffLine(kind: .context, text: "let hull = Hull()"),
        DiffLine(kind: .deletion, text: "hull.paint(.white)"),
        DiffLine(kind: .addition, text: "hull.paint(.red)"),
        DiffLine(kind: .addition, text: "hull.seal()"),
    ])

    private static let scenes: [(String, DiscardAlert)] = [
        ("hunk", .hunk(hunk, path: "Sources/Hull/Paint.swift", staged: .clean)),
        ("hunk-staged", .hunk(hunk, path: "Sources/Hull/Paint.swift", staged: .holdsAnotherVersion)),
        ("hunk-refused", .hunk(hunk, path: "Sources/Hull/Paint.swift", staged: .divergesFromTheWorktree)),
        ("file", .file(
            ChangedFile(path: "Sources/Hull/Paint.swift", change: .modified, additions: 14, deletions: 3),
            base: "main", hasDraft: true
        )),
    ]
}
#endif

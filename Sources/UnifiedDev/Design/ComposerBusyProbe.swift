import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum ComposerBusyProbe {
    private static let harness = ProbeHarness(subject: "composer-busy")

    static var isRequested: Bool { harness.isRequested }

    static func runAndExit() -> Never {
        guard Bundle.main.bundleIdentifier != "io.akira.unifieddev" else { exit(1) }
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { await run() }
        RunLoop.main.run()
        exit(1)
    }

    private static let size = CGSize(width: 900, height: 160)

    private static let grown = CGSize(width: 900, height: 260)

    private static var span: Double { Double(max(1, ProbeHarness.count("--span", or: 4))) }

    private static let budget = 0.05

    private static let tolerance = 4

    private static let drawnFloor = 500

    private struct Subject: View {
        var isBusy: Bool

        var body: some View {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .composerBox(isFocused: .constant(false), isFloating: true, isBusy: isBusy)
                .padding(Metrics.gutter)
        }
    }

    private struct Redrawn: View {
        var isTurning: Bool

        @State private var angle: Double = 0

        var body: some View {
            Subject(isBusy: false)
                .overlay {
                    RoundedRectangle(cornerRadius: ComposerBox.floatingCorner, style: .continuous)
                        .stroke(gradient, lineWidth: ComposerBusyOutline.width)
                        .padding(Metrics.gutter)
                }
                .onAppear {
                    guard isTurning else { return }
                    withAnimation(
                        .linear(duration: ComposerBusyOutline.lap).repeatForever(autoreverses: false)
                    ) { angle = 360 }
                }
        }

        private var gradient: AngularGradient {
            AngularGradient(
                stops: ComposerBusyOutline.stops.map {
                    .init(color: Palette.running.opacity($0.opacity), location: $0.location)
                },
                center: .center,
                angle: .degrees(angle)
            )
        }
    }

    private static func run() async {
        let control = await share(of: Redrawn(isTurning: true))
        let subject = await share(of: Subject(isBusy: true))
        var likeness: [String: JSONValue] = [:]
        var isLikeTheOldOutline = true
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (place, grownTo) in [("settled", nil), ("grown", grown)] as [(String, CGSize?)] {
                let label = "\(name)-\(place)"
                let ring = await still(of: Subject(isBusy: true), "ring-\(label)", appearance, grownTo)
                let redrawn = await still(of: Redrawn(isTurning: false), "redrawn-\(label)", appearance, grownTo)
                let idle = await still(of: Subject(isBusy: false), "idle-\(label)", appearance, grownTo)
                let kindled = await still(
                    of: Subject(isBusy: false), becoming: Subject(isBusy: true),
                    "kindled-\(label)", appearance, grownTo
                )
                let apart = difference(ring, redrawn)
                let drawn = difference(ring, idle)
                let lit = difference(kindled, redrawn)
                likeness[label] = .object([
                    "worstAgainstRedrawn": .integer(apart.worst),
                    "worstKindledAgainstRedrawn": .integer(lit.worst),
                    "pixelsDrawn": .integer(drawn.pixelsOver),
                ])
                let isAlike = apart.worst <= tolerance && lit.worst <= tolerance
                if !isAlike || drawn.pixelsOver < drawnFloor { isLikeTheOldOutline = false }
            }
        }

        let isControlRed = control.share > budget
        let isSubjectGreen = subject.share <= budget && subject.turning == 1
        let passed = isControlRed && isSubjectGreen && isLikeTheOldOutline
        var report = harness.conditions(window: nil)
        report["budget"] = .number(budget)
        report["redrawnShare"] = .number(control.share)
        report["ringShare"] = .number(subject.share)
        report["ringsTurning"] = .integer(subject.turning)
        report["stills"] = .object(likeness)
        report["passed"] = .bool(passed)
        harness.write(.object(report), echo: true)
        exit(passed ? 0 : 1)
    }

    private static func panel<Content: View>(_ content: Content) -> (NSWindow, NSHostingView<Content>) {
        let panel = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let host = NSHostingView(rootView: content)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0.02
        panel.ignoresMouseEvents = true
        panel.level = .floating
        return (panel, host)
    }

    private static func share(of content: some View) async -> (share: Double, turning: Int) {
        let (panel, host) = panel(content)
        panel.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(2))
        let before = ProbeHarness.mainThreadCPUSeconds()
        try? await Task.sleep(for: .seconds(span))
        let spent = ProbeHarness.mainThreadCPUSeconds() - before
        let earlier = turns(in: host.layer)
        try? await Task.sleep(for: .milliseconds(300))
        let later = turns(in: host.layer)
        panel.close()
        let turning = zip(earlier, later).count { isClockwise(from: $0, to: $1) }
        return (spent / span, earlier.count == later.count ? turning : 0)
    }

    private static func isClockwise(from earlier: Double, to later: Double) -> Bool {
        let moved = later - earlier
        return atan2(sin(moved), cos(moved)) > 0
    }

    private static func still<Content: View>(
        of content: Content, becoming later: Content? = nil,
        _ name: String, _ appearance: NSAppearance.Name, _ grownTo: CGSize?
    ) async -> NSBitmapImageRep? {
        let (panel, host) = panel(content)
        defer { panel.close() }
        panel.appearance = NSAppearance(named: appearance)
        await settle(panel)
        if let later {
            host.rootView = later
            try? await Task.sleep(for: .seconds(2 * ComposerBusyOutline.fade))
            await settle(panel)
        }
        if let grownTo {
            panel.setContentSize(grownTo)
            await settle(panel)
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: harness.outputPath).deletingLastPathComponent()
        try? bitmap.representation(using: .png, properties: [:])?
            .write(to: directory.appending(path: "composer-busy-\(name).png"))
        return bitmap
    }

    private static func settle(_ panel: NSWindow) async {
        for _ in 0..<3 {
            panel.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func difference(
        _ one: NSBitmapImageRep?, _ other: NSBitmapImageRep?
    ) -> (worst: Int, pixelsOver: Int) {
        guard let one, let other, let left = one.bitmapData, let right = other.bitmapData,
              one.pixelsWide == other.pixelsWide, one.pixelsHigh == other.pixelsHigh,
              one.bytesPerRow == other.bytesPerRow, one.samplesPerPixel == other.samplesPerPixel
        else { return (Int.max, 0) }
        let samples = one.samplesPerPixel
        var worst = 0
        var pixelsOver = 0
        for row in 0..<one.pixelsHigh {
            for column in 0..<one.pixelsWide {
                let start = row * one.bytesPerRow + column * samples
                let apart = (0..<samples).map { abs(Int(left[start + $0]) - Int(right[start + $0])) }.max() ?? 0
                worst = max(worst, apart)
                if apart > tolerance { pixelsOver += 1 }
            }
        }
        return (worst, pixelsOver)
    }

    private static func turns(in layer: CALayer?) -> [Double] {
        guard let layer else { return [] }
        let own = layer is CAGradientLayer
            ? [layer.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double ?? 0]
            : []
        return (layer.sublayers ?? []).reduce(own) { $0 + turns(in: $1) }
    }
}
#endif

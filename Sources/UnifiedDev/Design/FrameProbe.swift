import AppKit
import SwiftUI
import QuartzCore
import Core

@MainActor
enum FrameProbe {
    private static let harness = ProbeHarness(subject: "frame")

    static var isRequested: Bool { harness.isRequested }

    private static var driver: String { ProbeHarness.text("--probe-driver", or: "mouse") }

    static var wantsInspector: Bool { !ProbeHarness.isPresent("--probe-no-inspector") }
    private static var sweeps: Int { ProbeHarness.count("--probe-sweeps", or: 6) }
    private static var selection: String? { ProbeHarness.value(for: "--probe-select") }

    private static var gesture: String { ProbeHarness.text("--probe-gesture", or: "sidebar") }

    private static var requestedPane: PaneKind? {
        ProbeHarness.value(for: "--probe-pane").flatMap(PaneKind.init(rawValue:))
    }

    private static var paneURL: String { ProbeHarness.text("--probe-url", or: "") }

    static func schedule() {
        Task { @MainActor in await run() }
    }

    private static func run() async {
        let (window, contentView) = await harness.window()
        ProbeHarness.appModel?.isInspectorVisible = wantsInspector

        if let selection {
            OpenWorkspaceNotification.post(WorkspaceID(selection))
            try? await Task.sleep(for: .seconds(6))
        }

        if let requestedPane { await openPane(requestedPane) }

        try? await Task.sleep(for: .seconds(4))

        var split: NSSplitView?
        if gesture != "window" {
            guard let found = sidebarSplitView(in: contentView) else {
                harness.fail("no sidebar NSSplitView found")
            }
            guard found.arrangedSubviews.count >= 2 else {
                harness.fail("sidebar split view has \(found.arrangedSubviews.count) panes")
            }
            split = found
        }

        let recorder = FrameRecorder(view: contentView) { [weak split, weak window] in
            gesture == "window"
                ? (window?.frame.width ?? 0)
                : (split?.arrangedSubviews.first?.frame.width ?? 0)
        }

        await drag(split: split, window: window, sweeps: 1, recorder: nil)
        try? await Task.sleep(for: .seconds(1))

        harness.markStarted()

        PaneLayoutTiming.reset()
        PaneLayoutTiming.isEnabled = true
        TranscriptHoldCensus.reset()
        recorder.start()
        let cpuBefore = ProbeHarness.mainThreadCPUSeconds()
        let wallBefore = CACurrentMediaTime()
        await drag(split: split, window: window, sweeps: sweeps, recorder: recorder)
        mainThreadCPU = ProbeHarness.mainThreadCPUSeconds() - cpuBefore
        wallClock = CACurrentMediaTime() - wallBefore
        recorder.stop()
        PaneLayoutTiming.isEnabled = false

        harness.write(report(recorder: recorder, window: window, split: split))
        exit(0)
    }

    private static func sidebarSplitView(in root: NSView) -> NSSplitView? {
        var found: [NSSplitView] = []
        func walk(_ view: NSView) {
            if let split = view as? NSSplitView { found.append(split) }
            for subview in view.subviews { walk(subview) }
        }
        walk(root)
        guard !found.isEmpty else { return nil }
        return found.first { candidate in
            !found.contains { other in other !== candidate && candidate.isDescendant(of: other) }
        } ?? found.first
    }

    private static func dividerX(_ split: NSSplitView) -> CGFloat {
        let first = split.arrangedSubviews[0]
        return first.frame.maxX + split.dividerThickness / 2
    }

    private static func drag(
        split: NSSplitView?, window: NSWindow, sweeps: Int, recorder: FrameRecorder?
    ) async {
        if gesture == "window" {
            switch driver {
            case "programmatic": await resizeWindow(window, sweeps: sweeps, paced: true)
            case "throughput": await resizeWindow(window, sweeps: sweeps, paced: false)
            default: await resizeWindowWithMouse(window, sweeps: sweeps)
            }
            return
        }
        guard let split else { return }
        switch driver {
        case "programmatic": await dragProgrammatically(split: split, sweeps: sweeps, paced: true)
        case "throughput": await dragProgrammatically(split: split, sweeps: sweeps, paced: false)
        default: await dragWithMouse(split: split, window: window, sweeps: sweeps)
        }
    }

    private static func resizeWindow(_ window: NSWindow, sweeps: Int, paced: Bool) async {
        let start = window.frame
        for offset in sweepOffsets(sweeps: sweeps) {
            var frame = start
            frame.size.width = start.width + offset
            window.setFrame(frame, display: true)
            if paced {
                try? await Task.sleep(for: .microseconds(8_333))
            } else {
                await nextRunLoopTurn()
            }
        }
        window.setFrame(start, display: true)
        try? await Task.sleep(for: .milliseconds(300))
    }

    private static func resizeWindowWithMouse(_ window: NSWindow, sweeps: Int) async {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let corner = CGPoint(x: window.frame.maxX - 2, y: window.frame.minY + 2)
        let flipped = CGPoint(x: corner.x, y: screen.frame.maxY - corner.y)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(400))

        let pid = ProcessInfo.processInfo.processIdentifier
        let sequence = sweepOffsets(sweeps: sweeps)
        await harness.onEventThread(polling: .milliseconds(4)) {
            ProbeHarness.post(.leftMouseDown, at: flipped, pid: pid)
            Thread.sleep(forTimeInterval: 0.05)
            for offset in sequence {
                ProbeHarness.post(
                    .leftMouseDragged, at: CGPoint(x: flipped.x + offset, y: flipped.y), pid: pid
                )
                Thread.sleep(forTimeInterval: 1.0 / 120.0)
            }
            ProbeHarness.post(.leftMouseUp, at: flipped, pid: pid)
        }
        try? await Task.sleep(for: .milliseconds(300))
    }

    private static func openPane(_ kind: PaneKind) async {
        guard let workspace = AppModel.probeSelectedModel else { return }
        NewPane.open(kind, in: workspace, url: paneURL) {
            WorkspaceTabsStore.shared.select($0, in: workspace)
        }
        try? await Task.sleep(for: .seconds(kind == .chat ? 3 : 6))
    }

    private static let travel: CGFloat = 150

    private static func dragWithMouse(split: NSSplitView, window: NSWindow, sweeps: Int) async {
        let start = dividerX(split)
        let pointInSplit = CGPoint(x: start, y: split.bounds.midY)
        let inWindow = split.convert(pointInSplit, to: nil)
        let onScreen = window.convertPoint(toScreen: inWindow)

        guard let screen = window.screen ?? NSScreen.main else { return }
        let flipped = CGPoint(x: onScreen.x, y: screen.frame.maxY - onScreen.y)

        let sequence = sweepOffsets(sweeps: sweeps)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(400))

        let pid = ProcessInfo.processInfo.processIdentifier
        await harness.onEventThread(polling: .milliseconds(4)) {
            ProbeHarness.post(.leftMouseDown, at: flipped, pid: pid)
            Thread.sleep(forTimeInterval: 0.05)
            for offset in sequence {
                let point = CGPoint(x: flipped.x + offset, y: flipped.y)
                ProbeHarness.post(.leftMouseDragged, at: point, pid: pid)
                Thread.sleep(forTimeInterval: 1.0 / 120.0)
            }
            ProbeHarness.post(.leftMouseUp, at: CGPoint(x: flipped.x, y: flipped.y), pid: pid)
        }
        try? await Task.sleep(for: .milliseconds(300))
    }

    private static func dragProgrammatically(
        split: NSSplitView, sweeps: Int, paced: Bool
    ) async {
        let start = dividerX(split)
        let sequence = sweepOffsets(sweeps: sweeps)
        for offset in sequence {
            split.setPosition(start + offset, ofDividerAt: 0)
            if paced {
                try? await Task.sleep(for: .microseconds(8_333))
            } else {
                await nextRunLoopTurn()
            }
        }
        split.setPosition(start, ofDividerAt: 0)
        try? await Task.sleep(for: .milliseconds(300))
    }

    private static func nextRunLoopTurn() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private static func sweepOffsets(sweeps: Int) -> [CGFloat] {
        var offsets: [CGFloat] = []
        let step: CGFloat = 2
        for _ in 0..<sweeps {
            var x: CGFloat = 0
            while x > -travel { offsets.append(x); x -= step }
            while x < 0 { offsets.append(x); x += step }
        }
        return offsets
    }

    private static func report(
        recorder: FrameRecorder, window: NSWindow, split: NSSplitView?
    ) -> JSONValue {
        let intervals = recorder.intervals.map { $0 * 1000 }
        let sorted = intervals.sorted()
        func percentile(_ fraction: Double) -> Double {
            ProbeStats.percentile(fraction, of: sorted)
        }
        let total = intervals.reduce(0, +)
        let mean = intervals.isEmpty ? 0 : total / Double(intervals.count)
        let steps = sweepOffsets(sweeps: sweeps).count

        let own: [String: JSONValue] = [
            "driver": .string(driver),
            "gesture": .string(gesture),
            "pane": .string(requestedPane?.rawValue ?? "whatever was open"),
            "selection": .string(selection ?? "home"),
            "drawnRows": .integer(TranscriptDrawn.rows),
            "inspector": .bool(ProbeHarness.appModel?.isInspectorPresented ?? false),
            "restoredWorkspace": .string(
                UserDefaults.standard.string(forKey: "sidebar.lastWorkspaceID") ?? "none"
            ),
            "frames": .integer(intervals.count),
            "durationMs": .number(total),
            "meanMs": .number(mean),
            "meanFps": .number(mean > 0 ? 1000 / mean : 0),
            "medianMs": .number(percentile(0.5)),
            "medianFps": .number(percentile(0.5) > 0 ? 1000 / percentile(0.5) : 0),
            "p95Ms": .number(percentile(0.95)),
            "p99Ms": .number(percentile(0.99)),
            "maxMs": .number(sorted.last ?? 0),
            "framesOver16ms": .integer(intervals.filter { $0 > 16.7 }.count),
            "framesOver33ms": .integer(intervals.filter { $0 > 33.4 }.count),
            "sidebarWidth": .number(Double(split?.arrangedSubviews[0].frame.width ?? 0)),
            "widthMin": .number(Double(recorder.widths.min() ?? 0)),
            "widthMax": .number(Double(recorder.widths.max() ?? 0)),
            "widthSteps": .integer(Set(recorder.widths).count),
            "dragSteps": .integer(steps),
            "mainThreadCpuMs": .number(mainThreadCPU * 1000),
            "wallMs": .number(wallClock * 1000),
            "mainThreadBusyFraction": .number(wallClock > 0 ? mainThreadCPU / wallClock : 0),
            "cpuMsPerStep": .number(mainThreadCPU * 1000 / Double(max(1, steps))),
            "paneLayout": .map(PaneLayoutTiming.summary()),
            "transcriptHold": .map(TranscriptHoldCensus.summary()),
            "histogramMs": .numbers(intervals),
        ]
        return .object(own.merging(harness.conditions(window: window)) { mine, _ in mine })
    }

    private static var mainThreadCPU: Double = 0
    private static var wallClock: Double = 0
}

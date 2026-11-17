import AppKit
import Core
import SwiftUI

@MainActor
enum UnboundedHeightProbe {
    private static let harness = ProbeHarness(subject: "unbounded-height")

    static var isRequested: Bool { harness.isRequested }

    static func schedule() { Task { @MainActor in await run() } }

    static let hostWidths: [UnboundedHeightSubject.Host: [CGFloat]] = [
        .mainWindow: [Metrics.inspectorMinimum, Metrics.inspectorWidth, Metrics.centreColumnMinimum, 900],
        .sheet: [320, Metrics.centreColumnMinimum, 640],
        .settingsWindow: [210, 320, 520],
        .menuBarPanel: [MenuBarPanelPlacement.width],
        .welcomeWindow: [WelcomeView.contentWidth],
        .hoverPanel: [HoverCardWidth.minimum, HoverCardWidth.ceiling],
        .composerPopover: [240, 320, 420],
    ]

    private static func run() async {
        guard PreviewIdentity.isPreview(bundleIdentifier: Bundle.main.bundleIdentifier),
              (try? PreviewLaunch.root()) != nil else {
            harness.fail(
                "requires a worktree preview with a database and a workspaces root inside it, not "
                    + (Bundle.main.bundleIdentifier ?? "nothing")
            )
        }
        Snapshot.applyRequestedAppearance()
        let (window, content) = await harness.window()
        window.setFrameOrigin(GalleryOffscreen.parked)
        window.alphaValue = 1
        guard let app = ProbeHarness.appModel else { harness.fail("no app model") }
        app.isInspectorVisible = true
        for _ in 0..<200 where !app.isLoaded { try? await Task.sleep(for: .milliseconds(100)) }

        var failures: [String] = []
        var report: [String: JSONValue] = [:]

        let control = await controls()
        report["control"] = .object(control.json)
        if !control.discriminates {
            failures.append(
                "the archive card that emptied the window in #241 drew a "
                    + "\(control.before.height)pt window holding \(control.before.ink.lowest) "
                    + "where the card the fix leaves draws \(control.after.height)pt holding "
                    + "\(control.after.ink.onArrival), which does not tell them apart, so "
                    + "nothing below this means anything"
            )
        }

        let staging = Staging(
            app: app,
            workspace: app.workspaces.first,
            session: await firstSession(app: app)
        )
        if staging.workspace == nil {
            failures.append("the scenario seeded no live workspace, so nothing could be staged")
        }

        var comparisons: [String: HeightComparison] = [:]
        for subject in UnboundedHeightSubject.all {
            comparisons[subject.key] = await compare(subject, in: staging)
        }

        let drawn = await readWindows(
            app: app, window: window, content: content, staging: staging, drawing: control.after
        )
        report["windows"] = .object(drawn.json)

        var verdicts: [String: JSONValue] = [:]
        for subject in UnboundedHeightSubject.all {
            guard let comparison = comparisons[subject.key] else { continue }
            let judged = judge(subject, comparison: comparison, looked: drawn[subject.key])
            verdicts[subject.key] = judged.report
            failures += judged.failures
        }
        report["subjects"] = .object(verdicts)
        report["captures"] = .array(captures)
        report["passed"] = .bool(failures.isEmpty)
        report["failures"] = .strings(failures)
        harness.write(.object(report), echo: true)
        exit(failures.isEmpty ? 0 : 1)
    }

    private static func judge(
        _ subject: UnboundedHeightSubject, comparison: HeightComparison, looked: Looked
    ) -> (report: JSONValue, failures: [String]) {
        let verdict = UnboundedHeightSubject.verdict(
            comparison: comparison, read: looked.wasRead, escaped: looked.escaped
        )
        var failures: [String] = []
        if verdict == .unmeasured {
            failures.append(
                "\(subject.key) was not measured: staged \(comparison.wasStaged), screen read "
                    + "\(looked.wasRead). A reading that was never taken is not a view that draws"
            )
        }
        if !comparison.wasStaged {
            failures.append(
                "\(subject.key) asked for \(comparison.saying.reference.height)pt at "
                    + "\(HeightSweep.referenceWidth)pt, so nothing was staged for it and its "
                    + "reading is of an empty view"
            )
        }
        if verdict.blocksRelease {
            failures.append(
                "\(subject.key) at \(subject.file):\(subject.line) drew a "
                    + "\(looked.seen.height)pt window holding \(looked.seen.ink.lowest) where "
                    + "the archive card the #241 fix leaves draws \(looked.floor.height)pt and "
                    + "the same view with a sentence that cannot wrap holds "
                    + "\(looked.shortened.ink.lowest), measured in \(looked.place), so the "
                    + "height request escaped"
            )
        }
        let report = JSONValue.object([
            "subject": subject.json,
            "heights": comparison.json,
            "looked": looked.json,
            "verdict": .string(verdict.rawValue),
        ])
        return (report, failures)
    }

    private static func firstSession(app: AppModel) async -> Session? {
        guard let workspace = app.workspaces.first else { return nil }
        let model = app.model(for: workspace)
        await model.reloadSessions()
        return model.sessions.first
    }

    static func compare(
        _ subject: UnboundedHeightSubject, in staging: Staging
    ) async -> HeightComparison {
        HeightComparison(
            saying: await sweep(subject, in: staging, saying: UnboundedHeightSubject.longSentence),
            shortened: await sweep(subject, in: staging, saying: shortSentence)
        )
    }

    static func sweep(
        _ subject: UnboundedHeightSubject, in staging: Staging, saying said: String
    ) async -> HeightSweep {
        var atHostWidths: [HeightRequest] = []
        for width in hostWidths[subject.host] ?? [Metrics.centreColumnMinimum] {
            atHostWidths.append(
                await request(view(for: subject, in: staging, saying: said), at: width)
            )
        }
        return HeightSweep(
            reference: await request(
                view(for: subject, in: staging, saying: said), at: HeightSweep.referenceWidth
            ),
            atHostWidths: atHostWidths
        )
    }

    static func request(_ rootView: some View, at width: CGFloat) async -> HeightRequest {
        let host = NSHostingView(rootView: rootView.frame(width: width))
        let window = NSWindow(
            contentRect: NSRect(
                origin: GalleryOffscreen.parked, size: NSSize(width: width, height: 10)
            ),
            styleMask: [], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(120))
        host.layoutSubtreeIfNeeded()
        let height = host.fittingSize.height
        window.contentView = nil
        window.close()
        return HeightRequest(width: width, height: height)
    }
}

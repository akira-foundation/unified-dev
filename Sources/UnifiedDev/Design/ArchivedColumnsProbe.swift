import AppKit
import Core

@MainActor
enum ArchivedColumnsProbe {
    private static let harness = ProbeHarness(subject: "archived-columns")
    static var isRequested: Bool { harness.isRequested }

    static func schedule() { Task { @MainActor in await run() } }

    private static var drawsSidebar: Bool {
        UnifiedDevApp.widths.sidebarMaximum(
            sharing: ProbeHarness.points("--window-available-width", or: .greatestFiniteMagnitude),
            withInspector: false
        ) != nil
    }

    struct Drawn {
        var columns: [Column]
        var identifiers: Set<String>
        var glass = -1.0
        var settled = -1.0

        struct Column {
            var collapsed: Bool
            var width: CGFloat
            var onScreen: Bool
            var ink: Double
        }

        var sidebar: Column? { columns.count == 3 ? columns[0] : nil }
        var centre: Column? { columns.count == 3 ? columns[1] : nil }
        var inspector: Column? { columns.count == 3 ? columns[2] : nil }

        var showsSomething: Bool { columns.contains { $0.onScreen } }

        var json: JSONValue {
            .object([
                "columns": .array(columns.map {
                    .object([
                        "collapsed": .bool($0.collapsed),
                        "width": .number(Double($0.width)),
                        "onScreen": .bool($0.onScreen),
                        "ink": .number($0.ink),
                    ])
                }),
                "archiveView": .bool(identifiers.contains(ArchivedWorkspaceView.identifier)),
            ])
        }
    }

    private static func run() async {
        guard PreviewIdentity.isPreview(bundleIdentifier: Bundle.main.bundleIdentifier),
              (try? PreviewLaunch.root()) != nil else {
            harness.fail(
                "requires a worktree preview with a database and a workspaces root inside it, not "
                    + (Bundle.main.bundleIdentifier ?? "nothing")
            )
        }
        let (window, content) = await harness.window()
        guard let app = ProbeHarness.appModel, let store = app.store else { harness.fail("no app store") }
        app.isInspectorVisible = true
        for _ in 0..<200 where !app.isLoaded { try? await Task.sleep(for: .milliseconds(100)) }

        var failures: [String] = []
        var report: [String: JSONValue] = [:]
        var fixtureRoot: URL?
        var fixtureRepo: Repo?

        do {
            let built: Fixture
            if ProbeHarness.isPresent("--archived-columns-seeded") {
                let archived = await app.archivedWorkspaces()
                guard let subject = archived.first else { harness.fail("the database holds no archived workspace") }
                guard let live = app.workspaces.first else { harness.fail("the database holds no live workspace") }
                built = Fixture(archived: subject, live: live)
            } else {
                let root = FileManager.default.temporaryDirectory
                    .appendingPathComponent("unifieddev-archived-columns-\(UUID().uuidString)")
                fixtureRoot = root
                built = try await makeFixture(app: app, store: store, at: root) { fixtureRepo = $0 }
            }
            guard let archived = await app.archivedWorkspaces().first(where: { $0.id == built.archived.id })
            else { harness.fail("the fixture workspace did not archive") }

            func look(_ name: String) async -> Drawn {
                try? await Task.sleep(for: .milliseconds(2_300))
                let before = await glass(window)
                window.layoutIfNeeded()
                content.layoutSubtreeIfNeeded()
                var drawn = measure(window)
                drawn.glass = before
                window.contentView?.needsDisplay = true
                window.displayIfNeeded()
                try? await Task.sleep(for: .milliseconds(600))
                let after = await glass(window)
                drawn.settled = after
                var json = drawn.json
                if case .object(var fields) = json {
                    fields["glassBefore"] = .number(before)
                    fields["glassAfter"] = .number(after)
                    fields["window"] = chrome(window)
                    fields["windows"] = .array(NSApp.windows.map { other in
                        .object([
                            "title": .string(other.title),
                            "visible": .bool(other.isVisible),
                            "probed": .bool(other === window),
                            "key": .bool(other.isKeyWindow),
                            "width": .number(other.frame.width),
                            "height": .number(other.frame.height),
                            "kind": .string("\(type(of: other))"),
                        ])
                    })
                    json = .object(fields)
                }
                report[name] = json
                return drawn
            }

            func drawsAsMuchAsHome(_ drawn: Drawn, than home: Drawn, _ name: String) {
                let baseline = WindowInk(onArrival: home.glass, afterRedraw: home.settled)
                let reading = WindowInk(onArrival: drawn.glass, afterRedraw: drawn.settled)
                switch reading.verdict(against: baseline) {
                case .drew:
                    return
                case .unreadable:
                    failures.append("the screen could not be read for \(name)")
                case .stoppedDrawing:
                    failures.append(
                        "\(name) put \(reading.lowest) on the screen where Home puts "
                            + "\(baseline.lowest), so the window stopped drawing"
                    )
                }
            }

            func expect(
                _ drawn: Drawn, _ name: String, sidebar: Bool, inspector: Bool, archiveView: Bool
            ) {
                guard drawn.columns.count == 3 else {
                    failures.append("\(name) drew \(drawn.columns.count) columns instead of three")
                    return
                }
                if !drawn.showsSomething { failures.append("\(name) left the window with nothing drawn") }
                if drawn.centre?.onScreen != true { failures.append("\(name) folded the centre column away") }
                if drawn.sidebar?.onScreen != sidebar {
                    failures.append("\(name) drew the sidebar as \(drawn.sidebar?.onScreen == true), wanted \(sidebar)")
                }
                if drawn.inspector?.onScreen != inspector {
                    failures.append(
                        "\(name) drew the inspector as \(drawn.inspector?.onScreen == true), wanted \(inspector)"
                    )
                }
                if drawn.identifiers.contains(ArchivedWorkspaceView.identifier) != archiveView {
                    failures.append("\(name) drew the archive view as \(!archiveView), wanted \(archiveView)")
                }
            }

            let sidebar = drawsSidebar

            app.selection = .home
            app.forgetWorkspace(built.archived.id)
            let fromHome = await look("home-first")

            await app.open(workspaceID: built.archived.id)
            let archivedFromHome = await look("archived-from-home")
            drawsAsMuchAsHome(archivedFromHome, than: fromHome, "an archived workspace opened from Home")
            expect(
                archivedFromHome, "an archived workspace opened from Home",
                sidebar: sidebar, inspector: false, archiveView: true
            )

            app.selection = .workspace(built.live.id)
            expect(
                await look("live"), "a live workspace",
                sidebar: sidebar, inspector: true, archiveView: false
            )

            app.openArchived(archived)
            let reopened = await look("archived")
            drawsAsMuchAsHome(reopened, than: fromHome, "an archived workspace")
            expect(
                reopened, "an archived workspace",
                sidebar: sidebar, inspector: false, archiveView: true
            )

            NotificationCenter.default.post(name: .unifieddevToggleSidebar, object: nil)
            var blankSamples = 0
            var centrelessSamples = 0
            var samples = 0
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(50))
                window.layoutIfNeeded()
                let sample = measure(window)
                samples += 1
                if !sample.showsSomething { blankSamples += 1 }
                if sample.centre?.onScreen != true { centrelessSamples += 1 }
            }
            report["whileHiding"] = .object([
                "samples": .integer(samples),
                "blank": .integer(blankSamples),
                "withoutCentre": .integer(centrelessSamples),
            ])
            if blankSamples > 0 {
                failures.append("hiding the sidebar left the window blank for \(blankSamples) of \(samples) samples")
            }
            if centrelessSamples > 0 {
                failures.append("hiding the sidebar took the centre column away for \(centrelessSamples) of \(samples) samples")
            }
            expect(
                await look("archived-while-hiding"),
                "an archived workspace with the sidebar hidden",
                sidebar: false, inspector: false, archiveView: true
            )

            app.selection = .home
            expect(
                await look("home"), "Home with the sidebar hidden",
                sidebar: false, inspector: false, archiveView: false
            )

            app.selection = .workspace(built.live.id)
            expect(
                await look("live-again"), "a live workspace with the sidebar hidden",
                sidebar: false, inspector: true, archiveView: false
            )

            NotificationCenter.default.post(name: .unifieddevToggleSidebar, object: nil)
            app.openArchived(archived)
            expect(
                await look("archived-again"), "an archived workspace after the sidebar came back",
                sidebar: sidebar, inspector: false, archiveView: true
            )

            if let split = window.contentView?.mainSplitView(),
               let controller = split.delegate as? NSSplitViewController,
               controller.splitViewItems.count >= 3 {
                controller.splitViewItems[0].isCollapsed = true
                let collapsed = await look("archived-after-a-native-collapse")
                report["adoptedTheNativeCollapse"] = .bool(app.isSidebarHidden)
                if sidebar, !app.isSidebarHidden {
                    failures.append("a sidebar the window collapsed was not taken as the owner hiding it")
                }
                expect(
                    collapsed, "an archived workspace after the window collapsed the sidebar",
                    sidebar: false, inspector: false, archiveView: true
                )
            }
        } catch {
            failures.append("the fixture could not be built: \(error)")
        }

        app.selection = .home
        if let fixtureRepo { await app.removeRepository(fixtureRepo) }
        if let fixtureRoot { try? FileManager.default.removeItem(at: fixtureRoot) }

        report["passed"] = .bool(failures.isEmpty)
        report["failures"] = .strings(failures)
        harness.write(.object(report), echo: true)
        exit(failures.isEmpty ? 0 : 1)
    }

}

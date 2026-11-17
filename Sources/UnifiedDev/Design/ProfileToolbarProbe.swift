import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum ProfileToolbarProbe {
    private static let flag = "--profile-toolbar-probe"

    static var isRequested: Bool { CommandLine.arguments.contains(flag) }

    static func runAndExit() -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { await run() }
        RunLoop.main.run()
        exit(1)
    }

    private static var directory: String {
        ProbeHarness.text(flag, or: NSTemporaryDirectory() + "unifieddev-profile-toolbar")
    }

    private struct Scene {
        var name: String
        var profiles: [Profile]
        var active: ProfileID
        var drawsSidebar = true
        var sidebarWidth: CGFloat = 260
        var barIsHidden = false
    }

    private static let unified = Profile(
        id: .initial, name: "Unified", folder: "unified", colour: Accent.all[0], symbol: "square.stack.3d.up"
    )
    private static let akira = Profile(
        id: ProfileID("akira"), name: "akira-foundation", folder: "akira", colour: Accent.all[2], symbol: "leaf"
    )
    private static let longNamed = Profile(
        id: ProfileID("long"),
        name: "A client whose name goes on far longer than any sidebar is wide",
        folder: "long",
        colour: Accent.all[3],
        symbol: "building.2"
    )

    private static func minimum(_ profile: Profile) -> CGFloat {
        ProfileToolbarLabel.titleBarWidth(forNameWidth: ProfileSwitcherMenu.nameWidth(profile.name))
    }

    private static var scenes: [Scene] { [
        Scene(name: "open", profiles: [unified, akira], active: akira.id),
        Scene(name: "collapsed", profiles: [unified, akira], active: akira.id, drawsSidebar: false),
        Scene(name: "one-profile", profiles: [unified], active: unified.id),
        Scene(name: "long-name", profiles: [unified, longNamed], active: longNamed.id),
        Scene(name: "long-name-wide", profiles: [unified, longNamed], active: longNamed.id, sidebarWidth: 340),
        Scene(name: "minimum-unified", profiles: [unified, akira], active: unified.id, sidebarWidth: minimum(unified)),
        Scene(name: "minimum-akira", profiles: [unified, akira], active: akira.id, sidebarWidth: minimum(akira)),
        Scene(
            name: "minimum-long-name", profiles: [unified, longNamed], active: longNamed.id,
            sidebarWidth: minimum(longNamed)
        ),
        Scene(name: "full-screen-bar-hidden", profiles: [unified, akira], active: akira.id, barIsHidden: true),
    ] }

    private static func run() async {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var failures = 0
        for scene in scenes {
            for scheme in [ColorScheme.light, .dark] where await !shoot(scene, scheme: scheme) {
                failures += 1
            }
        }
        report("active=\(NSApp.isActive) visibleWindows=\(NSApp.windows.filter(\.isVisible).count) failures=\(failures)")
        exit(failures == 0 ? 0 : 1)
    }

    private static func report(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    private static func window(for scene: Scene, scheme: ColorScheme) -> NSWindow {
        NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let size = CGSize(width: 1200, height: 320)
        let host = NSHostingController(rootView: split(scene)
            .environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentViewController = host
        window.setContentSize(size)
        return window
    }

    private static func switcher(_ scene: Scene, placement: ToolbarItemPlacement) -> ProfileSwitcherToolbar {
        ProfileSwitcherToolbar(
            placement: placement,
            profiles: scene.profiles,
            activeID: scene.active,
            drawsSidebar: scene.drawsSidebar,
            barIsHidden: scene.barIsHidden,
            sidebarWidth: scene.sidebarWidth,
            onSwitch: { _ in },
            onNew: {},
            onSettings: {}
        )
    }

    private static func split(_ scene: Scene) -> some View {
        NavigationSplitView(columnVisibility: .constant(scene.drawsSidebar ? .all : .doubleColumn)) {
            List {
                SidebarNavRow(title: "Home", icon: "house")
            }
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
            .navigationSplitViewColumnWidth(min: scene.sidebarWidth, ideal: scene.sidebarWidth, max: scene.sidebarWidth)
            .toolbar {
                if scene.drawsSidebar {
                    switcher(scene, placement: scene.barIsHidden ? .automatic : .secondaryAction)
                }
            }
        } content: {
            Color.clear
                .navigationSplitViewColumnWidth(min: 400, ideal: 700, max: .infinity)
                .toolbar {
                    if !scene.drawsSidebar {
                        switcher(scene, placement: .navigation)
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button("Add", systemImage: "plus") {}
                    }
                }
        } detail: {
            Color.clear
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        }
        .navigationTitle("Workspace")
    }

    private static func shoot(_ scene: Scene, scheme: ColorScheme) async -> Bool {
        let window = window(for: scene, scheme: scheme)
        try? await Task.sleep(for: .milliseconds(900))
        guard let frame = window.contentView?.superview else { return false }
        let measured = measure(scene, window: window, frame: frame)
        if scheme == .dark { report(measured.line) }
        guard measured.isSound else { return false }
        frame.layoutSubtreeIfNeeded()
        frame.displayIfNeeded()
        guard let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return false }
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(filePath: "\(directory)/\(scene.name)-\(scheme).png"))) != nil
    }

    private static func measure(_ scene: Scene, window: NSWindow, frame: NSView) -> (line: String, isSound: Bool) {
        let lights = window.standardWindowButton(.zoomButton)
            .map { Int($0.convert($0.bounds, to: nil).maxX) } ?? -1
        let views = descendants(of: frame)
        let platterFrames = views.filter { "\(type(of: $0))".contains("ToolbarItemHostingView") }
            .map { $0.convert($0.bounds, to: nil) }
            .sorted { $0.minX < $1.minX }
        let platters = platterFrames.map { "\(Int($0.minX))..\(Int($0.maxX))" }
        let order = window.toolbar?.items.map(\.itemIdentifier.rawValue) ?? []
        let toggle = order.firstIndex { $0.contains("toggleSidebar") }
        let separator = order.firstIndex { $0.contains("splitViewSeparator") }
        let overflow = views.contains { "\(type(of: $0))".lowercased().contains("overflow") }
        let line = "\(scene.name): lights end \(lights), platters \(platters), "
            + "toggle index \(toggle ?? -1), separator index \(separator ?? -1), column \(Int(scene.sidebarWidth)), overflow \(overflow)"
        let clearOfLights = platterFrames.first.map { Int($0.minX) > lights } ?? false
        return (line, clearOfLights && !overflow)
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }
}
#endif

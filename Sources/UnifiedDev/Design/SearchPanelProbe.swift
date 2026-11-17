import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum SearchPanelProbe {
    private static let flag = "--search-panel-probe"
    private static let width: CGFloat = 640
    private static let height: CGFloat = 420

    static var isRequested: Bool { CommandLine.arguments.contains(flag) }

    static func runAndExit() -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { await run() }
        RunLoop.main.run()
        exit(1)
    }

    private static var directory: String {
        ProbeHarness.text(flag, or: NSTemporaryDirectory() + "unifieddev-search-panel")
    }

    private static func run() async {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var written = 0
        for scheme in [ColorScheme.light, .dark] where await shoot(scheme) { written += 1 }
        report(.aqua)
        report(.darkAqua)
        exit(written == 2 ? 0 : 1)
    }

    private static func report(_ name: NSAppearance.Name) {
        guard let appearance = NSAppearance(named: name) else { return }
        appearance.performAsCurrentDrawingAppearance {
            let plate = rgb(.unemphasizedSelectedContentBackgroundColor, over: 0xFFFFFF)
            let lines = [
                ("title and detail on the selected plate", NSColor.labelColor),
                ("disabled title and detail on the selected plate", NSColor.secondaryLabelColor),
            ].map { label, colour in
                "\(name.rawValue) \(label): \(String(format: "%.2f", Contrast.ratio(rgb(colour, over: plate), plate)))"
            }
            FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        }
    }

    private static func rgb(_ colour: NSColor, over ground: UInt32) -> UInt32 {
        guard let srgb = colour.usingColorSpace(.sRGB) else { return ground }
        let packed = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].reduce(UInt32(0)) {
            ($0 << 8) | UInt32(($1 * 255).rounded())
        }
        return Contrast.composited(packed, over: ground, at: Double(srgb.alphaComponent))
    }

    private static func shoot(_ scheme: ColorScheme) async -> Bool {
        let size = CGSize(width: width, height: height)
        let host = NSHostingController(rootView: panel
            .padding(24)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Palette.windowBackground)
            .environment(\.colorScheme, scheme))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentViewController = host
        window.setContentSize(size)
        try? await Task.sleep(for: .milliseconds(600))
        guard let view = window.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(filePath: "\(directory)/rows-\(scheme).png"))) != nil
    }

    private static var panel: some View {
        MenuPanel {
            VStack(alignment: .leading, spacing: SearchPanelRowMetrics.gap) {
                heading("Profiles")
                SearchPanelProfileRow(
                    hit: SearchPanelProfileHit(profile: foundation, highlights: [0, 1], score: 52, keyText: "\u{2303}\u{2318}2"),
                    isSelected: true, onPick: {}, onHover: {}
                )
                heading("Workspaces")
                SearchPanelWorkspaceRow(
                    hit: workspaceHit("feat: falar com chats de todos os profiles", highlights: [5, 6]),
                    isSelected: true, onPick: {}, onHover: {}
                )
                SearchPanelWorkspaceRow(
                    hit: workspaceHit("auditar issues abertas e fechar as feitas", highlights: [20, 21]),
                    isSelected: false, onPick: {}, onHover: {}
                )
                heading("Commands")
                command(.focusPane, highlights: [0, 1], isEnabled: false, isSelected: false)
                command(.findPrevious, highlights: [0, 8], isEnabled: true, isSelected: false)
                command(.focusPane, highlights: [0, 1], isEnabled: false, isSelected: true)
                command(.findPrevious, highlights: [0, 8], isEnabled: true, isSelected: true)
            }
            .padding(.vertical, Metrics.spacingSmall)
        }
    }

    private static func heading(_ title: String) -> some View {
        Text(title)
            .font(Typo.micro)
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, Metrics.inset)
    }

    private static func command(
        _ action: MenuBarAction, highlights: [Int], isEnabled: Bool, isSelected: Bool
    ) -> some View {
        SearchPanelCommandRow(
            hit: SearchPanelCommandHit(item: MenuBarCatalogue[action], highlights: highlights),
            isEnabled: isEnabled, isSelected: isSelected, onPick: {}, onHover: {}
        )
    }

    private static let foundation = Profile(
        id: ProfileID("foundation"), name: "Foundation", folder: "foundation", colour: "4C8DF6", symbol: "building.2"
    )

    private static let repo = Repo(id: RepoID("repo"), name: "unified-dev", path: "/tmp/repo")

    private static func workspaceHit(_ name: String, highlights: [Int]) -> SearchPanelWorkspaceHit {
        SearchPanelWorkspaceHit(
            workspace: Workspace(
                id: WorkspaceID(name), repoID: repo.id, name: name, branch: "x", path: "/tmp/x",
                baseBranch: "main", lastActivityAt: Date(timeIntervalSinceNow: -60)
            ),
            repo: repo,
            highlights: highlights
        )
    }
}
#endif

import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum ProfileProbe {
    private static let flag = "--profile-probe"

    static var isRequested: Bool { CommandLine.arguments.contains(flag) }

    static func runAndExit() -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { await run() }
        RunLoop.main.run()
        exit(1)
    }

    private static var directory: String {
        ProbeHarness.text(flag, or: NSTemporaryDirectory() + "unifieddev-profile")
    }

    private struct Scene {
        var name: String
        var size: CGSize
        var view: AnyView
    }

    private struct SceneBody {
        var view: AnyView
        var size: CGSize
    }

    private static let unified = Profile(
        id: .initial, name: "Unified", folder: "unified", colour: Accent.all[0], symbol: "square.stack.3d.up"
    )
    private static let akira = Profile(
        id: ProfileID("akira"), name: "Akira", folder: "akira", colour: Accent.all[2], symbol: "leaf"
    )
    private static func run() async {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let missing = ProfileChoices.symbols.filter {
            NSImage(systemSymbolName: $0.name, accessibilityDescription: nil) == nil
        }
        let menu = NSHostingMenu(rootView: switcherMenuItems)
        var written = 0
        var wanted = 0
        for scene in scenes(menu: menu) {
            for scheme in [ColorScheme.light, .dark] {
                wanted += 1
                if await shoot(scene, scheme: scheme) { written += 1 }
            }
        }
        report([
            "wrote \(written) of \(wanted)",
            "unknown symbols: \(missing.map(\.name))",
            "menu: \(menu.items.map(describe))",
            "active=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue) "
                + "visibleWindows=\(NSApp.windows.filter(\.isVisible).count)",
        ])
        exit(written == wanted && missing.isEmpty ? 0 : 1)
    }

    private static func report(_ lines: [String]) {
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    private static func describe(_ menuItem: NSMenuItem) -> String {
        if menuItem.isSeparatorItem { return "---" }
        let mark = menuItem.image.map { $0.isTemplate ? "template" : "coloured" } ?? "no image"
        return "\(menuItem.title) [\(menuItem.state == .on ? "on" : "off"), \(mark)]"
    }

    private static var switcherMenuItems: some View {
        ProfileSwitcherItems(
            profiles: [unified, akira], activeID: akira.id, onSwitch: { _ in }, onNew: {}, onSettings: {}
        )
    }

    private static func sheet(
        _ draft: ProfileDraft,
        isNew: Bool = false,
        refusal: ProfileDeletionRefused? = nil,
        options: AgentAccountOptions = AgentAccountProbe.profileOptions
    ) -> SceneBody {
        SceneBody(
            view: AnyView(
                ProfileSheetBody(
                    draft: .constant(draft),
                    isNew: isNew,
                    deletionRefusal: refusal?.sentence,
                    onDelete: {},
                    onCancel: {},
                    onSave: {}
                ) {
                    if !isNew, draft.accounts == .own, !draft.accountsChanged {
                        AgentAccountRows(
                            options: options, failure: nil, onPick: { _, _ in }, onAddAccount: nil
                        )
                        ProfileAccountSignInButtons(
                            providers: [.claudeCode, .codex], profileName: draft.savedName, onSignIn: { _ in }
                        )
                    }
                }
            ),
            size: CGSize(
                width: ProfileSheetMetrics.width,
                height: isNew ? ProfileSheetMetrics.newHeight : ProfileSheetMetrics.editHeight
            )
        )
    }

    private static func menuRows(_ menu: NSMenu) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                ForEach(Array(menu.items.enumerated()), id: \.offset) { _, menuItem in
                    if menuItem.isSeparatorItem {
                        Divider()
                    } else {
                        HStack(spacing: Metrics.spacing) {
                            Image(systemName: menuItem.state == .on ? "checkmark" : "circle.dotted")
                                .opacity(menuItem.state == .on ? 1 : 0)
                            if let image = menuItem.image {
                                Image(nsImage: image)
                            }
                            Text(menuItem.title)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Metrics.gutter)
        )
    }

    private static func statusModule(_ profile: Profile) -> AnyView {
        var content = MenuBarPanelContent.make(MenuBarPanelContent.Input(
            workspaces: [],
            running: [],
            waiting: [],
            agentsByWorkspace: [:],
            quotas: [],
            accounts: [:],
            unanswered: [],
            withoutLimits: [],
            lastReported: [:],
            layout: UsageLayout(),
            hold: .none,
            now: Date(timeIntervalSince1970: 1_800_000_000),
            profile: profile
        ))
        content.needsSetup = false
        return AnyView(
            MenuBarStatusModule(content: content, focus: nil, openSettings: {})
                .padding(MenuBarModuleStyle.edge)
        )
    }

    private static func scenes(menu: NSMenu) -> [Scene] {
        var named = ProfileDraft.new(among: [unified])
        named.name = "Client"
        var blank = ProfileDraft(editing: akira, accounts: .own)
        var switching = ProfileDraft(editing: akira, accounts: .own)
        switching.accounts = .inherits
        blank.name = "  "
        let sheets: [(String, SceneBody)] = [
            ("sheet-new", sheet(.new(among: [unified, akira]), isNew: true)),
            ("sheet-new-named", sheet(named, isNew: true)),
            ("sheet-unified", sheet(ProfileDraft(editing: unified, accounts: .own), refusal: .initial)),
            ("sheet-with-projects", sheet(ProfileDraft(editing: akira, accounts: .own), refusal: .hasProjects(count: 2))),
            ("sheet-empty", sheet(ProfileDraft(editing: akira, accounts: .own))),
            ("sheet-inherits", sheet(ProfileDraft(editing: akira, accounts: .inherits))),
            ("sheet-switching", sheet(switching)),
            ("sheet-blank-name", sheet(blank)),
            ("sheet-long-account", sheet(
                ProfileDraft(editing: akira, accounts: .own), options: AgentAccountProbe.longNameProfileOptions
            )),
        ]
        return [
            Scene(name: "switcher-menu", size: CGSize(width: 260, height: 170), view: menuRows(menu)),
            Scene(name: "menubar-header", size: CGSize(width: 360, height: 130), view: statusModule(akira)),
            Scene(name: "bridge-section", size: CGSize(width: ProfileSheetMetrics.width, height: 210), view: AnyView(
                Form { ProfileBridgeRows(isOn: .constant(true), isEnabled: true, failure: nil) }.settingsForm()
            )),
        ] + bitbucketScenes + sheets.map { Scene(name: $0.0, size: $0.1.size, view: $0.1.view) }
    }

    private static var bitbucketScenes: [Scene] {
        let signedIn = BitbucketAccount(user: "kid", method: "oauth")
        let signedOut = BitbucketAccount(user: nil, method: nil)
        let cases: [(String, Profile, ProfileGitHubSource, BitbucketAccount?, Bool)] = [
            ("bitbucket-own-signed-out", akira, .own, signedOut, true),
            ("bitbucket-own-signed-in", akira, .own, signedIn, true),
            ("bitbucket-inherits", akira, .inherits, signedIn, true),
            ("bitbucket-initial", unified, .inherits, signedOut, true),
            ("bitbucket-not-installed", akira, .own, nil, false),
        ]
        return cases.map { name, profile, source, account, installed in
            Scene(name: name, size: CGSize(width: ProfileSheetMetrics.width, height: 220), view: AnyView(
                Form {
                    ProfileBitbucketRows(
                        profile: profile, source: source, account: account, installed: installed,
                        isChecking: false, onSignIn: { _ in }
                    )
                }.settingsForm()
            ))
        }
    }

    private static func shoot(_ scene: Scene, scheme: ColorScheme) async -> Bool {
        let host = NSHostingController(rootView: scene.view
            .environment(\.colorScheme, scheme)
            .background(Palette.surface)
            .transaction { $0.disablesAnimations = true }
            .frame(width: scene.size.width, height: scene.size.height))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: scene.size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentViewController = host
        host.view.frame = CGRect(origin: .zero, size: scene.size)
        host.view.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(400))
        host.view.displayIfNeeded()
        guard let bitmap = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else { return false }
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(filePath: "\(directory)/\(scene.name)-\(scheme).png"))) != nil
    }
}

#endif

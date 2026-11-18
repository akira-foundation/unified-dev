import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum SearchPanelProbe {
    private static let flag = "--search-panel-probe"
    private static let width: CGFloat = SearchPanelLayout.minimumWidth + 48
    private static let height: CGFloat = 600

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
        let shots: [(ColorScheme, ControlActiveState)] = [(.light, .key), (.dark, .key), (.light, .inactive), (.dark, .inactive)]
        for (scheme, state) in shots where await shoot(scheme, state) { written += 1 }
        exit(written == shots.count ? 0 : 1)
    }

    private static func shoot(_ scheme: ColorScheme, _ state: ControlActiveState) async -> Bool {
        let size = CGSize(width: width, height: height)
        let host = NSHostingController(rootView: panel
            .padding(24)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Palette.windowBackground)
            .environment(\.controlActiveState, state)
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
        return (try? png.write(to: URL(filePath: "\(directory)/panel-\(scheme)\(state == .key ? "" : "-inactive").png"))) != nil
    }

    private static var panel: some View {
        MenuPanel {
            SearchPanelScopes(counts: counts, scope: .constant(.all))
                .padding(.top, Metrics.spacingWide)

            VStack(alignment: .leading, spacing: SearchPanelRowMetrics.gap) {
                SearchPanelSectionHeading(title: "Commands")
                command(.previousWorkspace, highlights: [0, 1], isEnabled: true, isSelected: true)
                command(.findPrevious, highlights: [0, 5], isEnabled: false, isSelected: false)
                command(.newWorkspaceFromPullRequest, highlights: [0, 4], isEnabled: true, isSelected: false)
                SearchPanelSectionHeading(title: "Profiles")
                SearchPanelProfileRow(
                    hit: SearchPanelProfileHit(profile: profile, highlights: [0, 1], score: 52, keyText: "\u{2303}\u{2318}2"),
                    isSelected: false, onPick: {}, onHover: {}
                )
                SearchPanelSectionHeading(title: "Workspaces")
                SearchPanelWorkspaceRow(
                    hit: workspaceHit("Tidy the release notes", highlights: [5, 6]),
                    isSelected: false, onPick: {}, onHover: {}
                )
                SearchPanelSectionHeading(title: "Transcripts")
                SearchPanelTranscriptRow(hit: transcriptHit, isSelected: false, onPick: {}, onHover: {})
            }
            .padding(.vertical, Metrics.spacingSmall)

            SearchPanelFooter(
                keys: SearchPanelKeys.footer(for: .things, isSearching: true),
                summary: SearchPanelSummary.rows(counts.count(of: .all, searching: true))
            )
        }
    }

    private static var counts: HomeScopeCounts {
        var counts = HomeScopeCounts()
        counts.workspaces = 3
        counts.transcripts = 42
        counts.archived = 7
        return counts
    }

    private static func command(
        _ action: MenuBarAction, highlights: [Int], isEnabled: Bool, isSelected: Bool
    ) -> some View {
        SearchPanelCommandRow(
            hit: SearchPanelCommandHit(item: MenuBarCatalogue[action], highlights: highlights),
            isEnabled: isEnabled, isSelected: isSelected, onPick: {}, onHover: {}
        )
    }

    private static let profile = Profile(
        id: ProfileID("sample"), name: "Sample", folder: "sample", colour: "4C8DF6", symbol: "building.2"
    )

    private static let repo = Repo(id: RepoID("repo"), name: "sample-app", path: "/tmp/repo")

    private static func workspace(_ name: String) -> Workspace {
        Workspace(
            id: WorkspaceID(name), repoID: repo.id, name: name, branch: "x", path: "/tmp/x",
            baseBranch: "main", lastActivityAt: Date(timeIntervalSinceNow: -60)
        )
    }

    private static func workspaceHit(_ name: String, highlights: [Int]) -> SearchPanelWorkspaceHit {
        SearchPanelWorkspaceHit(workspace: workspace(name), repo: repo, highlights: highlights)
    }

    private static var transcriptHit: SearchPanelTranscriptHit {
        let found = workspace("Draft the onboarding copy")
        let snippet = TranscriptSnippet(segments: [
            .init(text: "\u{2026}the settings live in ", isMatch: false),
            .init(text: "Persistence", isMatch: true),
            .init(text: "/Settings.swift, next to the defaults\u{2026}", isMatch: false),
        ])
        let match = TranscriptMatch(
            messageID: 1, workspaceID: found.id, sessionID: SessionID("s"), sessionTitle: "Chat",
            seq: 1, kind: .assistantText, createdAt: Date(), snippet: snippet, score: 1
        )
        return SearchPanelTranscriptHit(
            result: TranscriptWorkspaceMatches(workspaceID: found.id, matches: [match], total: 12),
            workspace: found, repo: repo, isArchived: false
        )
    }
}
#endif

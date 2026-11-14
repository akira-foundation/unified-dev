#if DEBUG
import AppKit
import Core
import SwiftUI

@MainActor
enum StartingPointSuggestionProbe {
    private static let harness = ProbeHarness(subject: "starting-point-suggestions")
    static var isRequested: Bool { harness.isRequested }
    static func schedule() { Task { @MainActor in await run() } }

    private static func run() async {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            await render(name: name, appearance: appearance)
        }
        harness.write(.object(["rendered": .bool(true)]))
        exit(0)
    }

    private static var fixture: (suggestions: [StartingPointSuggestion], point: WorkspaceStartingPoint) {
        let now = Date()
        let review = PullRequestListing(
            number: 591, title: "Keep a merged workspace while its other branches are in flight",
            author: "kid", headRefName: "fix/591-merged-archive", baseRefName: "develop"
        )
        let authored = PullRequestListing(
            number: 594, title: "Share one pull request read between loops",
            author: "kid", headRefName: "perf/594-shared-read", baseRefName: "develop", isDraft: true
        )
        let reading = StartingPointReading(
            pullRequests: PullRequestsAwaitingViewer(reviewRequested: [review], authored: [authored]),
            issues: [AssignedIssue(number: 34, title: "Suggest starting points below the new workspace composer")],
            branches: [RecentBranch(name: "feat/shade", touched: now.addingTimeInterval(-5 * 3600))],
            readAt: now
        )
        let suggestions = StartingPointSuggestions.choose(reading, defaultBranch: "develop", holders: [:], now: now)
        return (suggestions, .pullRequest(authored))
    }

    private static func render(name: String, appearance: NSAppearance.Name) async {
        let fixture = self.fixture
        let host = NSHostingView(rootView: StartingPointSuggestionList(
            suggestions: fixture.suggestions, point: fixture.point, onPick: { _ in }
        )
        .padding(.vertical, 20)
        .frame(width: 760)
        .background(Palette.surface))
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 200)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(200))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            harness.fail("no bitmap")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let path = harness.outputPath + ".\(name).png"
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif

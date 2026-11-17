import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum SideConversationProbe {
    private static let harness = ProbeHarness(subject: "side-conversation")

    static var isRequested: Bool { harness.isRequested }

    static func runAndExit() -> Never {
        guard Bundle.main.bundleIdentifier != "io.akira.unifieddev" else { exit(1) }
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { await run() }
        RunLoop.main.run()
        exit(1)
    }

    private static let snapshot = SideConversation.Snapshot(
        parentID: SessionID("probe"), title: "Search ordering",
        capturedAt: Date(timeIntervalSince1970: 1_794_500_000), context: ""
    )

    private static let size = CGSize(width: 340, height: 620)

    private static func run() async {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            await render(panel(isOpen: true), "open-\(name)", appearance)
            await render(panel(isOpen: false, isBusy: true), "opening-\(name)", appearance)
            await render(
                panel(isOpen: false, error: "This chat cannot start a side conversation."),
                "failed-\(name)", appearance
            )
            await render(inspector(selected: .side), "picker-\(name)", appearance, size: CGSize(width: 260, height: 220))
        }
        harness.write(.object(["rendered": .bool(true)]))
        exit(0)
    }

    private static func panel(isOpen: Bool, isBusy: Bool = false, error: String? = nil) -> some View {
        SideConversationPanel(
            snapshot: isOpen ? snapshot : nil, error: error, isBusy: isBusy, isOpen: isOpen,
            isKeeping: false, mainAgentIsRunning: isOpen,
            onStartNew: {}, onClose: {}, onKeep: {}, onRetry: {}
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Why does the filter run before the sort?")
                        .padding(10)
                        .background(.quaternary, in: .rect(cornerRadius: 10))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Because the sort is stable and the filter drops most rows, so sorting what is left is cheaper and keeps the order the search asked for.")
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func inspector(selected: InspectorTab) -> some View {
        let tabs = InspectorTab.available(for: nil, hasSideConversation: true)
        return Menu {
            ForEach(tabs, id: \.self) { tab in
                Label(tab.rawValue, systemImage: tab == selected ? "checkmark" : tab.symbol)
            }
        } label: {
            Label(selected.rawValue, systemImage: selected.symbol)
        }
        .fixedSize()
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(tabs, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab == selected ? "checkmark" : tab.symbol)
                }
            }
            .font(.callout)
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func render(
        _ view: some View, _ name: String, _ appearance: NSAppearance.Name, size: CGSize = size
    ) async {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            harness.fail("no bitmap")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let path = harness.outputPath + ".\(name).png"
        guard let png = bitmap.representation(using: .png, properties: [:]) else { harness.fail("no PNG for \(name)") }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            harness.fail("\(path): \(error)")
        }
    }
}
#endif

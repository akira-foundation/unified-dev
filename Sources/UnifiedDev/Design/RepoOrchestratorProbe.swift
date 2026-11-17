import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum RepoOrchestratorProbe {
    private static let flag = "--repo-orchestrator-probe"

    static var isRequested: Bool { CommandLine.arguments.contains(flag) }

    static func runAndExit() -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { await run() }
        RunLoop.main.run()
        exit(1)
    }

    private static var directory: String {
        ProbeHarness.text(flag, or: NSTemporaryDirectory() + "unifieddev-repo-orchestrator")
    }

    private static let size = CGSize(width: 620, height: 220)

    private static func run() async {
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("\(directory): \(error)\n".utf8))
            exit(1)
        }
        var written = 0
        for scheme in [ColorScheme.light, .dark] {
            for isOn in [false, true] where await shoot(isOn: isOn, scheme: scheme) {
                written += 1
            }
        }
        FileHandle.standardError.write(Data("wrote \(written) of 4\n".utf8))
        exit(written == 4 ? 0 : 1)
    }

    private static func shoot(isOn: Bool, scheme: ColorScheme) async -> Bool {
        let form = Form {
            RepoSettingSwitchRows(copy: RepoOrchestratorSection.copy, isOn: .constant(isOn), isEnabled: true, failure: nil)
        }
        .settingsForm()
        .scrollDisabled(true)
        let host = NSHostingController(rootView: form
            .environment(\.colorScheme, scheme)
            .background(Palette.surface)
            .transaction { $0.disablesAnimations = true }
            .frame(width: size.width, height: size.height))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentViewController = host
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(400))
        host.view.displayIfNeeded()
        guard let bitmap = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return false }
        if host.view.isFlipped {
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
        }
        host.view.layer?.render(in: context.cgContext)
        context.flushGraphics()
        guard let drawn = bitmap.representation(using: .png, properties: [:]) else { return false }
        let name = "repo-orchestrator-\(isOn ? "on" : "off")-\(scheme)"
        do {
            try drawn.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        } catch {
            FileHandle.standardError.write(Data("\(name): \(error)\n".utf8))
            return false
        }
        return true
    }
}
#endif

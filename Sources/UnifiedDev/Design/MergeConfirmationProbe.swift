import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum MergeConfirmationProbe {
    private static let flag = "--merge-confirmation-probe"
    private static let size = CGSize(width: 340, height: 230)

    static var isRequested: Bool { CommandLine.arguments.contains(flag) }

    static func runAndExit() -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { await run() }
        RunLoop.main.run()
        exit(1)
    }

    private static var directory: String {
        ProbeHarness.text(flag, or: NSTemporaryDirectory() + "unifieddev-merge-confirmation")
    }

    private static func run() async {
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("\(directory): \(error)\n".utf8))
            exit(1)
        }
        var written = 0
        let scenes: [(String, InstructionAuthority)] = [("own", .project), ("fork", .appOnly)]
        for (name, authority) in scenes {
            for scheme in [ColorScheme.light, .dark] where await shoot(name, authority, scheme: scheme) {
                written += 1
            }
        }
        FileHandle.standardError.write(Data("wrote \(written) of \(scenes.count * 2)\n".utf8))
        exit(written == scenes.count * 2 ? 0 : 1)
    }

    private static let pullRequest = PullRequest(
        number: 42, title: "Better glyphs", url: "https://github.com/ada/glyphs/pull/42", state: "OPEN",
        mergeable: "MERGEABLE", checks: .passing, branch: "feature/glyphs", baseBranch: "main"
    )

    private static func shoot(_ name: String, _ authority: InstructionAuthority, scheme: ColorScheme) async -> Bool {
        let view = MergeConfirmationPopover(
            pullRequest: pullRequest, baseBranch: "main", localWork: nil, method: .squash,
            authority: authority, canMerge: true, tint: Palette.positive, onConfirm: {}, onCancel: {}
        )
        guard let drawn = await OffscreenSnapshot.png(
            of: view, size: size, scheme: scheme, background: Palette.surfaceRaised
        ) else { return false }
        return (try? drawn.write(to: URL(filePath: directory + "/\(name)-\(scheme).png"))) != nil
    }
}
#endif

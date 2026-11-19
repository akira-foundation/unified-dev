import Testing
import Foundation
@testable import Core

@Suite("Transcript home")
struct TranscriptHomeTests {
    private let ours = URL(filePath: "/Users/ada", directoryHint: .isDirectory)
    private let preview = "io.akira.unifieddev.dev.worktree-spend"

    @Test("the real app never takes its transcript home from anywhere but the owner's home")
    func realAppIgnoresTheOverride() {
        let value = TranscriptHome.overrideValue(
            bundleIdentifier: Store.primaryBundleIdentifier,
            environment: [TranscriptHome.override: "/tmp/elsewhere"],
            info: [TranscriptHome.override: "/tmp/elsewhere"]
        )
        #expect(value == nil)
        #expect(TranscriptHome.resolve(
            bundleIdentifier: Store.primaryBundleIdentifier,
            home: ours,
            environment: [:],
            overriddenBy: value
        ) == ours)
    }

    @Test("a preview reads the transcripts seeded inside it")
    func previewTakesTheOverride() {
        let value = TranscriptHome.overrideValue(
            bundleIdentifier: preview,
            environment: [:],
            info: [TranscriptHome.override: "/tmp/preview/transcripts"]
        )
        #expect(value == "/tmp/preview/transcripts")
        #expect(TranscriptHome.resolve(
            bundleIdentifier: preview, home: ours, environment: [:], overriddenBy: value
        ).path == "/tmp/preview/transcripts")
    }

    @Test("the bundle is read before the environment, so a terminal cannot move a preview")
    func bundleWinsOverEnvironment() {
        let value = TranscriptHome.overrideValue(
            bundleIdentifier: preview,
            environment: [TranscriptHome.override: "/tmp/from-the-shell"],
            info: [TranscriptHome.override: "/tmp/from-the-bundle"]
        )
        #expect(value == "/tmp/from-the-bundle")
    }

    @Test("a preview with no transcript home of its own reads nothing, rather than the owner's")
    func previewWithoutAHomeReadsNothing() {
        let resolved = TranscriptHome.resolve(
            bundleIdentifier: preview, home: ours, environment: [:], overriddenBy: nil
        )
        #expect(resolved == TranscriptHome.nowhere)
        #expect(resolved != ours)
    }

    @Test("an override pointing at the owner's transcripts is read as nothing, not as theirs")
    func overridePointingAtTheirsReadsNothing() {
        for refused in ["/Users/ada", "/Users/ada/.claude", "/Users/ada/.codex"] {
            #expect(TranscriptHome.resolve(
                bundleIdentifier: preview, home: ours, environment: [:], overriddenBy: refused
            ) == TranscriptHome.nowhere)
        }
    }

    @Test("nothing may be seeded without an override, so the owner's transcripts are never written to")
    func seedingNeedsAnOverride() {
        #expect(TranscriptHome.seedable(overriddenBy: nil, home: ours, environment: [:]) == nil)
        #expect(TranscriptHome.seedable(overriddenBy: "", home: ours, environment: [:]) == nil)
        #expect(TranscriptHome.seedable(overriddenBy: "/tmp/preview", home: ours, environment: [:]) != nil)
    }

    @Test("the owner's own transcript directories are never seeded into")
    func seedingRefusesTheirs() {
        for refused in ["/Users/ada", "/Users/ada/.claude", "/Users/ada/.codex/sessions"] {
            #expect(TranscriptHome.seedable(overriddenBy: refused, home: ours, environment: [:]) == nil)
        }
    }

    @Test("a directory named in CLAUDE_CONFIG_DIR is theirs too")
    func seedingRefusesTheEnvironmentHome() {
        let environment = ["CLAUDE_CONFIG_DIR": "/Users/ada/dotfiles/claude"]
        #expect(TranscriptHome.seedable(
            overriddenBy: "/Users/ada/dotfiles/claude/projects", home: ours, environment: environment
        ) == nil)
    }

    @Test("a directory named in CODEX_HOME is theirs too")
    func seedingRefusesTheCodexEnvironmentHome() {
        let environment = ["CODEX_HOME": "/Users/ada/dotfiles/codex"]
        #expect(TranscriptHome.seedable(
            overriddenBy: "/Users/ada/dotfiles/codex", home: ours, environment: environment
        ) == nil)
    }

    @Test("a transcripts directory that is a link to the owner's is refused")
    func seedingRefusesALink() throws {
        let home = URL(filePath: TestScratch.unique("their-home"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: home.appending(path: ".claude"), withIntermediateDirectories: true
        )
        let preview = URL(filePath: TestScratch.unique("preview"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: preview, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: preview.appending(path: ".claude"), withDestinationURL: home.appending(path: ".claude")
        )
        #expect(TranscriptHome.seedable(
            overriddenBy: preview.path, home: home, environment: [:]
        ) == nil)
    }

    @Test("a preview inside the owner's home is still seedable, because it is not their transcripts")
    func seedingAllowsAWorktree() {
        let worktree = "/Users/ada/code/app/.claude/worktrees/spend/.build/preview/transcripts"
        #expect(TranscriptHome.seedable(overriddenBy: worktree, home: ours, environment: [:]) != nil)
    }
}

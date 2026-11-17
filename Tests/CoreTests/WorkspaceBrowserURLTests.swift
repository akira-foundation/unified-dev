import Testing
import Foundation
@testable import Core

@Suite("Workspace browser URL", .scratchDirectory)
struct WorkspaceBrowserURLTests {
    private let environment = [
        "UD_PORT": "3100",
        "UD_PROJECT_NAME": "shop",
        "UD_WORKSPACE_NAME": "feature-checkout",
    ]
    private let worktree = TestScratch.unique("unifieddev-browser-url-bounded")

    @Test("the port is the answer when nothing states an address")
    func portIsTheFallback() {
        let address = WorkspaceBrowserURL.resolve(
            written: nil, stated: nil, environment: environment, port: 3100
        )
        #expect(address == "http://localhost:3100")
    }

    @Test("a workspace holding no port opens on nothing, as it did before any of this")
    func noPortIsEmpty() {
        let address = WorkspaceBrowserURL.resolve(
            written: nil, stated: nil, environment: [:], port: 0
        )
        #expect(address.isEmpty)
    }

    @Test("the settings file beats the port")
    func statedBeatsThePort() {
        let address = WorkspaceBrowserURL.resolve(
            written: nil, stated: "http://localhost:$UD_PORT/admin",
            environment: environment, port: 3100
        )
        #expect(address == "http://localhost:3100/admin")
    }

    @Test("what the script wrote beats the settings file")
    func writtenBeatsStated() {
        let address = WorkspaceBrowserURL.resolve(
            written: "https://shop-a1b2c3d4.test\n", stated: "http://localhost:$UD_PORT",
            environment: environment, port: 3100
        )
        #expect(address == "https://shop-a1b2c3d4.test")
    }

    @Test("an empty file falls through to the settings file")
    func emptyWrittenFallsThrough() {
        let address = WorkspaceBrowserURL.resolve(
            written: "\n  \n", stated: "https://stated.test", environment: environment, port: 3100
        )
        #expect(address == "https://stated.test")
    }

    @Test("what the workspace menu opens is what the project declares, expanded")
    func declaredReadsTheSettingsFile() {
        var settings = RepoSettings()
        settings.browserURL = "http://localhost:$UD_PORT/admin"
        let address = WorkspaceBrowserURL.declared(
            settings: settings, environment: environment, port: 3100
        )
        #expect(address == "http://localhost:3100/admin")
    }

    @Test("the workspace menu falls back to the port, and to nothing without one")
    func declaredFallsBackToThePort() {
        #expect(
            WorkspaceBrowserURL.declared(
                settings: RepoSettings(), environment: environment, port: 3100
            ) == "http://localhost:3100"
        )
        #expect(
            WorkspaceBrowserURL.declared(
                settings: RepoSettings(), environment: [:], port: 0
            ).isEmpty
        )
    }

    @Test("an address a workspace's own scripts wrote never reaches the default browser")
    func declaredIgnoresWhatTheScriptsWrote() throws {
        let worktree = TestScratch.unique("unifieddev-browser-url")
        let path = WorkspaceBrowserURL.path(inWorktree: worktree)
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
        )
        try "https://attacker.test/?leak\n".write(toFile: path, atomically: true, encoding: .utf8)

        var settings = RepoSettings()
        settings.browserURL = "https://stated.test"
        let inThePane = WorkspaceBrowserURL.read(
            worktree: worktree, settings: settings, environment: environment, port: 3100
        )
        let inTheMenu = WorkspaceBrowserURL.declared(
            settings: settings, environment: environment, port: 3100
        )
        #expect(inThePane == "https://attacker.test/?leak")
        #expect(inTheMenu == "https://stated.test")
    }

    @Test("the first line is the address, whatever follows it")
    func firstLineWins() {
        let address = WorkspaceBrowserURL.resolve(
            written: "https://shop.test/login\nnot this\n", stated: nil,
            environment: environment, port: 3100
        )
        #expect(address == "https://shop.test/login")
    }

    @Test("a missing scheme is filled in rather than refused")
    func schemeIsFilledIn() {
        let written = WorkspaceBrowserURL.resolve(
            written: "shop.test", stated: nil, environment: environment, port: 0
        )
        #expect(written == "http://shop.test")

        let stated = WorkspaceBrowserURL.resolve(
            written: nil, stated: "localhost:$UD_PORT", environment: environment, port: 3100
        )
        #expect(stated == "http://localhost:3100")
    }

    @Test("both spellings of a variable expand")
    func bothSpellingsExpand() {
        let expanded = WorkspaceBrowserURL.expand(
            "https://${UD_PROJECT_NAME}-$UD_WORKSPACE_NAME.test:$UD_PORT/",
            with: environment
        )
        #expect(expanded == "https://shop-feature-checkout.test:3100/")
    }

    @Test("a name nothing sets is left as it was typed")
    func unknownNamesSurvive() {
        #expect(
            WorkspaceBrowserURL.expand("http://localhost:$UD_PROT", with: environment)
                == "http://localhost:$UD_PROT"
        )
        #expect(
            WorkspaceBrowserURL.expand("http://localhost:${UD_PORT", with: environment)
                == "http://localhost:${UD_PORT"
        )
        #expect(WorkspaceBrowserURL.expand("cost: $5", with: environment) == "cost: $5")
        #expect(WorkspaceBrowserURL.expand("trailing $", with: environment) == "trailing $")
    }

    @Test("the file the scripts write is read from the worktree's scratch folder")
    func readsTheFile() throws {
        let worktree = TestScratch.unique("unifieddev-browser-url")
        let path = WorkspaceBrowserURL.path(inWorktree: worktree)
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
        )
        try "https://written.test\n".write(toFile: path, atomically: true, encoding: .utf8)

        var settings = RepoSettings()
        settings.browserURL = "https://stated.test"
        let address = WorkspaceBrowserURL.read(
            worktree: worktree, settings: settings, environment: environment, port: 3100
        )
        #expect(address == "https://written.test")
    }

    @Test("only the first 64 KiB of the file are read, so an address past them is never reached")
    func readsABoundedPrefix() throws {
        try writtenFile(String(repeating: "\n", count: 65_536) + "https://past-the-limit.test\n")
        #expect(readAddress() == "https://stated.test")
    }

    @Test("an address after a long run of blank lines is still found")
    func findsAnAddressAfterBlankLines() throws {
        try writtenFile(String(repeating: "\n", count: 65_000) + "https://inside.test\n")
        #expect(readAddress() == "https://inside.test")
    }

    @Test("a first line cut by the limit is not taken for an address")
    func refusesATruncatedLine() throws {
        try writtenFile("https://shop.test/" + String(repeating: "a", count: 70_000))
        #expect(readAddress() == "https://stated.test")
    }

    @Test("a file that is not UTF-8 falls through to the settings file")
    func refusesInvalidText() throws {
        let path = try writtenFile("")
        try Data([0x68, 0x74, 0x74, 0x70, 0xFF, 0xFE, 0x0A]).write(to: URL(filePath: path))
        #expect(readAddress() == "https://stated.test")
    }

    @Test("a character the limit cuts in two does not cost the address before it")
    func keepsTheAddressBeforeACutCharacter() throws {
        let head = "https://ok.test\n"
        let filler = String(repeating: "a", count: 65_536 - head.utf8.count - 1) + "\u{E9}"
        try writtenFile(head + filler)
        #expect(readAddress() == "https://ok.test")
    }

    @Test("a pipe in place of the file is not waited on", .timeLimit(.minutes(1)))
    func refusesAPipe() throws {
        let path = try writtenFile("")
        try FileManager.default.removeItem(atPath: path)
        #expect(mkfifo(path, 0o600) == 0)
        #expect(readAddress() == "https://stated.test")
    }

    @discardableResult
    private func writtenFile(_ contents: String) throws -> String {
        let path = WorkspaceBrowserURL.path(inWorktree: worktree)
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
        )
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func readAddress() -> String {
        var settings = RepoSettings()
        settings.browserURL = "https://stated.test"
        return WorkspaceBrowserURL.read(
            worktree: worktree, settings: settings, environment: environment, port: 3100
        )
    }

    @Test("a worktree with no such file uses the settings file")
    func missingFileFallsThrough() {
        var settings = RepoSettings()
        settings.browserURL = "http://localhost:$UD_PORT/admin"
        let address = WorkspaceBrowserURL.read(
            worktree: TestScratch.unique("unifieddev-browser-url-empty"),
            settings: settings, environment: environment, port: 3100
        )
        #expect(address == "http://localhost:3100/admin")
    }

    @Test("the file git cannot see is where the address goes")
    func theFileIsShielded() {
        #expect(WorktreeScratch.isShielded(WorkspaceBrowserURL.file))
    }
}

import Foundation
import Testing
@testable import Core

@Suite("Renewing the folder a probe draws in", .tags(.persistence), .scratchDirectory)
struct ProbeFolderTests {
    private func folder(_ name: String) -> URL {
        URL(filePath: TestScratch.unique(name), directoryHint: .isDirectory)
    }

    @Test func aFolderThatIsNotThereIsMadeAndMarked() throws {
        let root = folder("fresh")

        try ProbeFolder.renew(root)

        #expect(ProbeFolder.isMadeByAProbe(root))
    }

    @Test func aFolderAProbeMadeIsEmptiedBeforeItIsUsedAgain() throws {
        let root = folder("again")
        try ProbeFolder.renew(root)
        let leftover = root.appending(path: "leftover.txt")
        try Data("old".utf8).write(to: leftover)

        try ProbeFolder.renew(root)

        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(ProbeFolder.isMadeByAProbe(root))
    }

    @Test func aFolderNoProbeMadeIsLeftAlone() throws {
        let root = folder("owned")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let kept = root.appending(path: "notes.txt")
        try Data("mine".utf8).write(to: kept)

        #expect(throws: ProbeFolderError.notMadeByAProbe(root.path)) { try ProbeFolder.renew(root) }
        #expect(FileManager.default.fileExists(atPath: kept.path))
    }

    @Test func aFolderNoProbeMadeIsNamedInTheFailure() throws {
        let root = folder("older")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let failure = ProbeFolder.failureToRenew(root.path)

        #expect(failure?.contains(root.path) == true)
        #expect(ProbeFolder.failureToRenew(folder("clean").path) == nil)
    }

    @Test func aLinkToAFolderAProbeMadeIsLeftAlone() throws {
        let target = folder("target")
        try ProbeFolder.renew(target)
        let link = folder("link")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: ProbeFolderError.notMadeByAProbe(link.path)) { try ProbeFolder.renew(link) }
        #expect(ProbeFolder.isMadeByAProbe(target))
    }

    @Test func aLinkToNothingIsLeftAlone() throws {
        let link = folder("dangling")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder("nowhere"))

        #expect(throws: ProbeFolderError.notMadeByAProbe(link.path)) { try ProbeFolder.renew(link) }
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
    }

    @Test func discardingKeepsAFolderNoProbeMade() throws {
        let root = folder("kept")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        ProbeFolder.discard(root)

        #expect(FileManager.default.fileExists(atPath: root.path))
    }

    @Test func discardingRemovesAFolderAProbeMade() throws {
        let root = folder("made")
        try ProbeFolder.renew(root)

        ProbeFolder.discard(root)

        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

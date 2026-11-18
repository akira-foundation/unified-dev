import Foundation
import Testing
@testable import Core

@Suite("Deciding when an open diff is read again")
struct DiffLoadIdentityTests {
    private let workspace = WorkspaceID("w1")
    private let hull = ChangedFile(path: "src/hull.txt", change: .modified, additions: 3, deletions: 3)

    private func identity(
        file: ChangedFile? = nil,
        revisions: [String: String],
        isCollapsed: Bool = false,
        ignoringWhitespace: Bool = false
    ) -> DiffLoadIdentity {
        DiffLoadIdentity(
            workspaceID: workspace,
            file: file ?? hull,
            revisions: revisions,
            scope: .all,
            language: .plainText,
            isCollapsed: isCollapsed,
            ignoringWhitespace: ignoringWhitespace
        )
    }

    @Test("an edit that keeps both counts still asks for the diff again")
    func editKeepingCountsReloads() {
        let before = identity(revisions: ["src/hull.txt": "all:1.0:120:7"])
        let after = identity(revisions: ["src/hull.txt": "all:2.0:119:7"])
        #expect(before != after)
    }

    @Test("a file nobody touched keeps the diff it has")
    func untouchedFileKeepsItsDiff() {
        let revisions = ["src/hull.txt": "all:1.0:120:7"]
        #expect(identity(revisions: revisions) == identity(revisions: revisions))
    }

    @Test("an edit to another file leaves this diff alone")
    func otherFileEditKeepsThisDiff() {
        let before = identity(revisions: ["src/hull.txt": "all:1.0:120:7", "src/keel.txt": "all:1.0:10:8"])
        let after = identity(revisions: ["src/hull.txt": "all:1.0:120:7", "src/keel.txt": "all:3.0:12:8"])
        #expect(before == after)
    }

    @Test("an edit on disk that keeps the counts moves the revision the diff is keyed on")
    func onDiskEditMovesTheIdentity() throws {
        let worktree = FileManager.default.temporaryDirectory
            .appendingPathComponent("diff-load-identity-\(UUID().uuidString)")
        let folder = worktree.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: worktree) }
        let file = folder.appendingPathComponent("hull.txt")

        try "line twelve\nline thirteen\nline fourteen\n".write(to: file, atomically: false, encoding: .utf8)
        let before = identity(revisions: ReviewedFileFingerprint.revisions(
            for: [hull], worktree: worktree.path, base: "main", scope: .all
        ))
        try "line twelve\nline thirteen\nline catorze\n".write(to: file, atomically: false, encoding: .utf8)
        let after = identity(revisions: ReviewedFileFingerprint.revisions(
            for: [hull], worktree: worktree.path, base: "main", scope: .all
        ))

        #expect(before.file == after.file)
        #expect(before != after)
    }
}

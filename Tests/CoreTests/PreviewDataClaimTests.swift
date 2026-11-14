import Foundation
import Testing
@testable import Core

@Suite("Whose preview data a build would open", .scratchDirectory)
struct PreviewDataClaimTests {
    private func identity(_ worktree: String = "/tmp/wt/clever", branch: String) throws -> PreviewIdentity {
        try PreviewIdentity(worktree: worktree, branch: branch, label: nil)
    }

    private func record(of identity: PreviewIdentity) -> String {
        identity.fields.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
    }

    @Test("a second branch in the same worktree is refused the first preview's database")
    func anotherBranchIsRefused() throws {
        let first = try identity(branch: "fix/123-setup")
        let second = try identity(branch: "fix/135-menu")

        let refusal = PreviewDataClaim.refusal(for: second, recorded: record(of: first), databaseExists: true)

        #expect(refusal?.contains("belongs to UD #123") == true)
        #expect(refusal?.contains("UD #135 would open UD #123's projects") == true)
        #expect(refusal?.contains("`make preview-clean`") == true)
    }

    @Test("the record is the identity.env dev-build.sh writes, read by its app_name line alone")
    func readsTheRecordTheScriptWrites() throws {
        let second = try identity(branch: "fix/135-menu")

        #expect(PreviewDataClaim.record(in: "/r") == "/r/identity.env")
        #expect(PreviewDataClaim.refusal(for: second, recorded: "app_name=\n", databaseExists: true) == nil)
        #expect(PreviewDataClaim.refusal(for: second, recorded: "old_app_name=UD #1\n", databaseExists: true) == nil)
    }

    @Test("the same preview built again keeps its data")
    func samePreviewKeepsItsData() throws {
        let preview = try identity(branch: "fix/123-setup")

        #expect(PreviewDataClaim.refusal(for: preview, recorded: record(of: preview), databaseExists: true) == nil)
    }

    @Test("with no database, or no record of who made it, there is nothing to refuse")
    func nothingToClaim() throws {
        let first = try identity(branch: "fix/123-setup")
        let second = try identity(branch: "fix/135-menu")

        #expect(PreviewDataClaim.refusal(for: second, recorded: record(of: first), databaseExists: false) == nil)
        #expect(PreviewDataClaim.refusal(for: second, recorded: nil, databaseExists: true) == nil)
        #expect(PreviewDataClaim.refusal(for: second, recorded: "slug=clever\n", databaseExists: true) == nil)
    }

    @Test("the preview command reads the record and the database beside it, and exits 1 to refuse")
    func commandRefuses() throws {
        let worktree = TestScratch.unique("clever")
        let first = try identity(worktree, branch: "fix/123-setup")
        try FileManager.default.createDirectory(
            atPath: (first.databasePath as NSString).deletingLastPathComponent, withIntermediateDirectories: true
        )
        try record(of: first).write(toFile: PreviewDataClaim.record(in: first.root), atomically: true, encoding: .utf8)

        let arguments = ["claim", "--worktree", worktree, "--branch"]
        #expect(PreviewCommand.run(arguments + ["fix/135-menu"]).status == 0)

        FileManager.default.createFile(atPath: first.databasePath, contents: Data())
        let refused = PreviewCommand.run(arguments + ["fix/135-menu"])
        #expect(refused.status == 1)
        #expect(refused.error.contains("belongs to UD #123"))
        #expect(PreviewCommand.run(arguments + ["fix/123-setup"]).status == 0)
    }
}

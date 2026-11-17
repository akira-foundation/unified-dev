import Foundation
import Testing
@testable import Core

@Suite("Agent plans when archiving", .tags(.git, .destructive), .scratchDirectory)
struct AgentPlansTests {
    private static let plan = "docs/superpowers/plans/2026-11-03-canvas.md"

    private func makeWorkspace(
        ignoring: String = ".superpowers/\ndocs/superpowers/\n",
        trackingDocuments: Bool = false
    ) async throws -> (TempRepo, Repo, WorkspaceManager, Workspace) {
        let repo = try await TempRepo()
        try repo.write(".gitignore", ignoring)
        if trackingDocuments { try repo.write("docs/README.md", "tracked\n") }
        try await repo.commit("ignore the agent scaffolding")
        let manager = WorkspaceManager(store: try makeTestStore("agent-plans"))
        let registered = try await manager.addRepository(at: repo.path)
        let workspace = try await manager.createWorkspace(repo: registered, prompt: "Do the thing")
        return (repo, registered, manager, workspace)
    }

    @Test("a branch review written for the pull request gate does not hold an archive")
    func branchReviewIsDisposable() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace()
        defer { repo.cleanUp() }

        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(".superpowers/sdd/branch-review-fd85ace3.md", "verdict: clean\n")

        let report = try await manager.safetyReport(workspace: workspace, repo: registered)
        #expect(report.modifiedIgnoredFiles.isEmpty)

        try await manager.archive(workspace: workspace, repo: registered, deleteBranch: false)
        #expect(FileManager.default.fileExists(atPath: workspace.path) == false)
    }

    @Test("a plan only the worktree has reaches the original project and the archive goes ahead")
    func newPlanIsKept() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace()
        defer { repo.cleanUp() }

        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(Self.plan, "the plan\n")

        let report = try await manager.safetyReport(workspace: workspace, repo: registered)
        #expect(report.modifiedIgnoredFiles.isEmpty)

        try await manager.archive(workspace: workspace, repo: registered, deleteBranch: false)

        #expect(repo.read(Self.plan) == "the plan\n")
        #expect(FileManager.default.fileExists(atPath: workspace.path) == false)
    }

    @Test("a plan of the same name with other words refuses the archive and overwrites nothing")
    func collidingPlanRefuses() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace()
        defer { repo.cleanUp() }

        try repo.write(Self.plan, "the original\n")
        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(Self.plan, "the worktree's\n")

        let report = try await manager.safetyReport(workspace: workspace, repo: registered)
        #expect(report.modifiedIgnoredFiles == [Self.plan])

        let failure = await #expect(throws: WorkspaceError.self) {
            try await manager.archive(workspace: workspace, repo: registered, deleteBranch: false)
        }
        guard case .unsafeToArchive(let refused)? = failure else {
            Issue.record("expected the refusal to carry its report")
            return
        }
        #expect(refused.modifiedIgnoredFiles == [Self.plan])
        #expect(repo.read(Self.plan) == "the original\n")
        #expect(FileManager.default.fileExists(atPath: workspace.path))
    }

    @Test("a confirmed archive still copies the new plans and leaves the colliding one alone")
    func confirmedArchiveKeepsWhatItCan() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace()
        defer { repo.cleanUp() }

        let other = "docs/superpowers/specs/canvas-design.md"
        try repo.write(Self.plan, "the original\n")
        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(Self.plan, "the worktree's\n")
        try worktree.write(other, "the spec\n")

        try await manager.archive(workspace: workspace, repo: registered, deleteBranch: false, force: true)

        #expect(repo.read(Self.plan) == "the original\n")
        #expect(repo.read(other) == "the spec\n")
    }

    @Test("beside tracked documents a plan is still compared by its own name")
    func planFolderBesideTrackedDocuments() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace(trackingDocuments: true)
        defer { repo.cleanUp() }

        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(Self.plan, "the plan\n")

        let clean = try await manager.safetyReport(workspace: workspace, repo: registered)
        #expect(clean.modifiedIgnoredFiles.isEmpty)

        try repo.write(Self.plan, "the original\n")
        let colliding = try await manager.safetyReport(workspace: workspace, repo: registered)
        #expect(colliding.modifiedIgnoredFiles == [Self.plan])
    }

    @Test("other ignored files under the documents folder are still compared")
    func otherIgnoredDocumentsAreStillALoss() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace(
            ignoring: ".superpowers/\ndocs/\n"
        )
        defer { repo.cleanUp() }

        let worktree = TempRepo(existing: workspace.path)
        try worktree.write("docs/notes.md", "by hand\n")

        let withoutPlans = try await manager.safetyReport(workspace: workspace, repo: registered)
        #expect(withoutPlans.modifiedIgnoredFiles == ["docs/"])

        try worktree.write(Self.plan, "the plan\n")
        let withPlans = try await manager.safetyReport(workspace: workspace, repo: registered)
        #expect(withPlans.modifiedIgnoredFiles == ["docs/notes.md"])
    }

    @Test("uncommitted work in the original project is left exactly as it was")
    func originalProjectWithUncommittedWork() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace(trackingDocuments: true)
        defer { repo.cleanUp() }

        try repo.write("docs/README.md", "edited and not committed\n")
        try repo.write("docs/draft.md", "untracked\n")
        let statusBefore = try await Shell.check("git", ["status", "--porcelain"], cwd: repo.path).stdout

        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(Self.plan, "the plan\n")

        try await manager.archive(workspace: workspace, repo: registered, deleteBranch: false)

        let statusAfter = try await Shell.check("git", ["status", "--porcelain"], cwd: repo.path).stdout
        #expect(statusAfter == statusBefore)
        #expect(repo.read("docs/README.md") == "edited and not committed\n")
        #expect(repo.read("docs/draft.md") == "untracked\n")
        #expect(repo.read(Self.plan) == "the plan\n")
    }

    @Test(
        "a copy that cannot be written keeps the worktree, the plan and the row",
        arguments: [false, true]
    )
    func failedCopyKeepsTheWorktree(force: Bool) async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace()
        defer { repo.cleanUp() }

        let plans = (repo.path as NSString).appendingPathComponent("docs/superpowers/plans")
        try repo.write("docs/superpowers/plans/older.md", "older\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: plans)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: plans) }

        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(Self.plan, "the plan\n")

        let failure = await #expect(throws: CocoaError.self) {
            try await manager.archive(
                workspace: workspace, repo: registered, deleteBranch: false, force: force
            )
        }
        #expect(failure?.code == .fileWriteNoPermission)
        #expect(try FileManager.default.contentsOfDirectory(atPath: plans) == ["older.md"])

        #expect(worktree.read(Self.plan) == "the plan\n")
        #expect(repo.read(Self.plan) == nil)
        let row = try await manager.store.workspace(id: workspace.id)
        #expect(row?.state == .active)
    }

    @Test("deciding to refuse writes nothing into the original project")
    func refusalWritesNothing() async throws {
        let (repo, _, _, workspace) = try await makeWorkspace()
        defer { repo.cleanUp() }

        let other = "docs/superpowers/specs/canvas-design.md"
        try repo.write(Self.plan, "the original\n")
        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(Self.plan, "the worktree's\n")
        try worktree.write(other, "the spec\n")

        let kept = try await AgentPlans.keep(worktree: workspace.path, repo: repo.path, acceptingLoss: false)

        #expect(kept == false)
        #expect(repo.read(other) == nil)
        #expect(repo.read(Self.plan) == "the original\n")
    }

    @Test("an identical plan already in the original project lets the archive through")
    func identicalPlanArchives() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace()
        defer { repo.cleanUp() }

        try repo.write(Self.plan, "the plan\n")
        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(Self.plan, "the plan\n")

        try await manager.archive(workspace: workspace, repo: registered, deleteBranch: false)

        #expect(FileManager.default.fileExists(atPath: workspace.path) == false)
        #expect(repo.read(Self.plan) == "the plan\n")
    }

    @Test(
        "a link in the plan folder never brings its target into the original project",
        arguments: [Self.plan, "docs/superpowers/plans"]
    )
    func linkIsNotFollowed(linkPath: String) async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace()
        defer { repo.cleanUp() }

        let secretFolder = try await TempRepo()
        defer { secretFolder.cleanUp() }
        try secretFolder.write("credentials", "secret\n")
        let target = linkPath == Self.plan
            ? (secretFolder.path as NSString).appendingPathComponent("credentials")
            : secretFolder.path

        let worktree = TempRepo(existing: workspace.path)
        try worktree.write("docs/superpowers/keep.md", "keep\n")
        let link = (workspace.path as NSString).appendingPathComponent(linkPath)
        try FileManager.default.createDirectory(
            atPath: (link as NSString).deletingLastPathComponent, withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)

        let report = try await manager.safetyReport(workspace: workspace, repo: registered)
        #expect(report.modifiedIgnoredFiles == [linkPath])

        try await manager.archive(workspace: workspace, repo: registered, deleteBranch: false, force: true)

        #expect(repo.exists(linkPath) == false)
        #expect(repo.read("docs/superpowers/plans/credentials") == nil)
        #expect(repo.read("docs/superpowers/keep.md") == "keep\n")
    }

    @Test("a plan under a folder named like build output is still kept")
    func planInAFolderNamedLikeBuildOutput() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace()
        defer { repo.cleanUp() }

        let plan = "docs/superpowers/plans/build/pipeline.md"
        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(plan, "the plan\n")

        try await manager.archive(workspace: workspace, repo: registered, deleteBranch: false)

        #expect(repo.read(plan) == "the plan\n")
    }

    @Test("a project that ignores only the plans folder still has its plans kept")
    func narrowIgnorePattern() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace(
            ignoring: "docs/superpowers/plans/\n"
        )
        defer { repo.cleanUp() }

        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(Self.plan, "the plan\n")

        try await manager.archive(workspace: workspace, repo: registered, deleteBranch: false)

        #expect(repo.read(Self.plan) == "the plan\n")
        #expect(FileManager.default.fileExists(atPath: workspace.path) == false)
    }

    @Test("a plan with glob characters in its name is kept under that name")
    func planNameIsNotAPattern() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace(
            ignoring: "docs/superpowers/*.md\n"
        )
        defer { repo.cleanUp() }

        let plan = "docs/superpowers/[draft].md"
        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(plan, "the plan\n")

        try await manager.archive(workspace: workspace, repo: registered, deleteBranch: false)

        #expect(repo.read(plan) == "the plan\n")
    }

    @Test("an identical plan is no collision")
    func identicalPlanIsNoCollision() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace()
        defer { repo.cleanUp() }

        try repo.write(Self.plan, "the plan\n")
        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(Self.plan, "the plan\n")

        let report = try await manager.safetyReport(workspace: workspace, repo: registered)
        #expect(report.modifiedIgnoredFiles.isEmpty)
    }

    @Test("plans the original project does not ignore stay a loss and are not written into it")
    func originalProjectThatTracksPlansIsNotWritten() async throws {
        let (repo, registered, manager, workspace) = try await makeWorkspace(
            ignoring: ".superpowers/\n!docs/superpowers/\n"
        )
        defer { repo.cleanUp() }

        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(".gitignore", ".superpowers/\ndocs/superpowers/\n")
        try await worktree.commit("ignore plans on this branch only")
        try worktree.write(Self.plan, "the plan\n")

        let report = try await manager.safetyReport(workspace: workspace, repo: registered)
        #expect(report.modifiedIgnoredFiles == [Self.plan])

        try await manager.archive(workspace: workspace, repo: registered, deleteBranch: false, force: true)
        #expect(repo.read(Self.plan) == nil)
    }

    @Test("the plan folder is somebody's work and the review folder is not")
    func classification() {
        #expect(ReproduciblePaths.canBeRebuilt(".superpowers/"))
        #expect(ReproduciblePaths.canBeRebuilt("docs/superpowers/") == false)
    }

    @Test("a project git cannot answer for refuses to keep the plans rather than dropping them")
    func unanswerableProjectThrows() async throws {
        let (repo, _, _, workspace) = try await makeWorkspace()
        defer { repo.cleanUp() }
        let worktree = TempRepo(existing: workspace.path)
        try worktree.write(Self.plan, "the plan\n")
        let elsewhere = TestScratch.unique("not-a-repository")
        try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: true)

        await #expect(throws: ShellError.self) {
            try await AgentPlans.keep(worktree: workspace.path, repo: elsewhere, acceptingLoss: true)
        }
        #expect(worktree.read(Self.plan) == "the plan\n")
    }
}

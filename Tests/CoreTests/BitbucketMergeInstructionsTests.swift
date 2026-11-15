import Foundation
import Testing
@testable import Core

@Suite("Merging and opening a pull request on Bitbucket")
struct BitbucketMergeInstructionsTests {
    private static let bitbucketURL = "https://bitbucket.org/debtges/ledger/pull-requests/7"

    @Test("each merge method becomes the bkt strategy that performs it", arguments: [
        (GitHub.MergeMethod.merge, "--strategy merge_commit"),
        (.squash, "--strategy squash"),
        (.rebase, "--strategy rebase_fast_forward"),
    ])
    func strategies(method: GitHub.MergeMethod, flag: String) {
        #expect(method.flag(on: .bitbucket) == flag)
        #expect(method.flag(on: .gitHub) == method.flag)
    }

    @Test("a Bitbucket pull request's merge prompt names the strategy and bkt")
    func promptNamesStrategy() {
        let workspace = Workspace(
            repoID: Repo(name: "ledger", path: "/nowhere").id, name: "ledger", branch: "feat/7", path: "/nowhere/7",
            baseBranch: "develop"
        )
        let pullRequest = PullRequest(number: 7, title: "", url: Self.bitbucketURL, state: "OPEN", branch: "")
        let context = MergePromptContext(workspace: workspace, pullRequest: pullRequest, method: .squash)

        #expect(context.forge == .bitbucket)
        #expect(context.render(template: "{{method_flag}}").text == "--strategy squash")
        #expect(context.render(template: "{{title}}").text.hasPrefix("(bkt did not report"))
        #expect(context.render(template: "{{branch}}").text.hasPrefix("(bkt did not report"))
    }

    @Test("the merge turn carries Bitbucket's own steps, and GitHub's stay as they were")
    func mergeTurn() {
        let bitbucket = ProjectInstructions.turn(
            "Merge #7.", for: .merge, adding: .nothing, authority: .project, forge: .bitbucket
        )
        let gitHub = ProjectInstructions.turn("Merge #7.", for: .merge, adding: .nothing, authority: .project)

        #expect(bitbucket.contains(MergeInstructions.bitbucketCanonical))
        #expect(bitbucket.contains("bkt pr merge <number> --strategy <strategy> --close-source=false"))
        #expect(!bitbucket.contains("gh pr merge"))
        #expect(gitHub.contains(MergeInstructions.canonical))
        #expect(ProjectInstructions.canonical(for: .merge, authority: .appOnly, forge: .bitbucket)
            == MergeInstructions.bitbucketAppOnly)
        #expect(MergeInstructions.bitbucketAppOnly.contains(InstructionAuthority.checkoutIsData))
    }

    @Test("opening a pull request on Bitbucket asks for bkt pr create, with the project's file when it has one")
    func openingTurn() throws {
        let worktree = TestScratch.unique("bitbucket-pr-instructions")
        try FileManager.default.createDirectory(atPath: worktree, withIntermediateDirectories: true)

        let appOnly = PullRequestInstructions.bitbucketTurn("Open it.", in: worktree, authority: .appOnly)
        let fallback = PullRequestInstructions.bitbucketTurn("Open it.", in: worktree, authority: .project)
        #expect(appOnly.hasSuffix(PullRequestInstructions.bitbucketAppOnlyMarkdown))
        #expect(fallback.hasSuffix(PullRequestInstructions.bitbucketMarkdown))
        #expect(fallback.contains("bkt pr create --source"))
        #expect(!fallback.contains("gh pr create"))

        let folder = (worktree as NSString).appendingPathComponent(".unifieddev")
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try "Our own steps.\n".write(
            toFile: (worktree as NSString).appendingPathComponent(PullRequestInstructions.projectPath),
            atomically: true, encoding: .utf8
        )
        let project = PullRequestInstructions.bitbucketTurn("Open it.", in: worktree, authority: .project)
        #expect(project.contains(PullRequestInstructions.projectPath))
        #expect(!project.contains(PullRequestInstructions.bitbucketMarkdown))
    }

    @Test("Mark ready on Bitbucket defaults to bkt pr ready, and an edited template still wins")
    func markReady() {
        let overrides = PromptOverrides(defaults: TestDefaults.make("bitbucket-mark-ready-\(UUID().uuidString)").defaults)

        #expect(overrides.template(for: .markReadyForReview, forge: .bitbucket).contains("bkt pr ready"))
        #expect(overrides.template(for: .markReadyForReview).contains("gh pr ready"))
        overrides.set("Mine {{url}}", for: .markReadyForReview)
        #expect(overrides.template(for: .markReadyForReview, forge: .bitbucket) == "Mine {{url}}")
    }

    @Test("the transcript folds the Bitbucket steps away like GitHub's")
    func transcriptRecognisesSteps() {
        let sent = "Merge #7.\n\n" + MergeInstructions.bitbucketCanonical
        #expect(SentTurn.withoutInstructions(sent) == "Merge #7.")
    }
}

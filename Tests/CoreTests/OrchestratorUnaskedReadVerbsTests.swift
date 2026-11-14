import Testing
@testable import Core

@Suite("Only the read verbs of git and gh pass without asking")
struct OrchestratorUnaskedReadVerbsTests {
    @Test("a git read naming a program to run stays with the owner", arguments: [
        "git ls-remote -u prog .",
        "git ls-remote -uprog .",
        "git ls-remote -qu prog .",
        "git ls-remote -q -u prog origin",
        "git ls-remote --upload-pack=prog .",
        "git ls-remote --upload-pack prog .",
        "git ls-remote --exec=prog .",
        "git fetch --upload-pack=prog origin",
        "git fetch --upload-pack prog origin",
        "git fetch --exec=prog origin",
    ])
    func gitReadRunningAProgram(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a fetch moving refs through clustered short flags stays with the owner", arguments: [
        "git fetch -qf origin",
        "git fetch -qp origin",
        "git fetch -P origin",
        "git fetch -qP origin",
        "git fetch -qu origin",
        "git fetch -p origin",
        "git fetch -f origin",
        "git fetch -u origin",
        "git fetch origin tag v1.0",
        "git fetch --set-upstream origin main",
    ])
    func fetchMovingRefsThroughClusters(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a plain git read still passes", arguments: [
        "git ls-remote origin",
        "git ls-remote --tags origin",
        "git ls-remote -q --refs origin",
        "git ls-remote -bt origin develop",
        "git fetch -q origin",
        "git fetch origin develop",
    ])
    func gitReadPasses(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("a gh verb that writes with the owner's token stays with the owner", arguments: [
        "gh repo edit --visibility public",
        "gh repo edit o/r --description x",
        "gh repo create x --public",
        "gh repo fork",
        "gh release create v1",
        "gh release edit v1 --draft=false",
        "gh release upload v1 file",
        "gh pr create --title x",
        "gh pr review 1 --approve",
        "gh pr close 1",
        "gh pr edit 1 --title x",
        "gh pr comment 1 --body x",
        "gh pr ready 1",
        "gh pr reopen 1",
        "gh issue create --title x",
        "gh issue close 1",
        "gh issue edit 1 --title x",
        "gh issue comment 1 --body x",
        "gh workflow run test.yml",
        "gh workflow enable test.yml",
        "gh workflow disable test.yml",
        "gh run rerun 1",
        "gh run cancel 1",
        "gh run download 1",
        "gh label create x",
        "gh label edit x --color 000000",
        "gh label clone o/r",
        "gh pr",
        "gh repo",
    ])
    func ghWriteAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a gh read opening a browser stays with the owner", arguments: [
        "gh pr view 1 --web",
        "gh issue view 1 -w",
        "gh repo view --web",
        "gh run view 1 -w",
        "gh pr list --web",
        "gh search repos x --web",
        "gh pr view 1 -cw",
    ])
    func ghReadOpeningABrowserAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a gh read still passes", arguments: [
        "gh pr view 1",
        "gh pr view 1 --json title --jq '.title'",
        "gh pr list --state open",
        "gh pr status",
        "gh pr diff 1",
        "gh pr checks 1",
        "gh issue view 1",
        "gh issue list",
        "gh issue status",
        "gh run view 1 --log",
        "gh run list --branch x",
        "gh repo view o/r",
        "gh repo list o",
        "gh release view v1",
        "gh release list",
        "gh workflow view test.yml",
        "gh workflow list",
        "gh label list",
        "gh search prs x",
        "gh search code x",
        "gh api repos/o/r/pulls",
        "gh status",
        "gh run list -w test.yml",
        "gh api repos/o/r -i",
    ])
    func ghReadPasses(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("gh api writing through a clustered or long flag stays with the owner", arguments: [
        "gh api repos/o/r/git/refs/heads/main -iX DELETE",
        "gh api repos/o/r -iXDELETE",
        "gh api repos/o/r/issues -iftitle=x",
        "gh api repos/o/r/issues/1/comments -iFbody=x",
        "gh api repos/o/r/pulls/1/merge -X PUT",
        "gh api repos/o/r/issues --method=POST",
        "gh api graphql --raw-field query=x",
        "gh api repos/o/r/issues --input body.json",
    ])
    func ghApiWriteAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a gh read aimed at another host stays with the owner", arguments: [
        "gh repo view evil.example/o/r",
        "gh issue list -R evil.example/o/secret",
        "gh issue list -Revil.example/o/secret",
        "gh issue list --repo=evil.example/o/secret",
        "gh pr view https://evil.example/o/r/pull/1",
        "gh api user --hostname evil.example",
        "gh api user --hostname=evil.example",
        "gh issue list -R intranet/o/secret",
        "gh issue list -cRintranet/o/secret",
        "gh repo view localhost:8443/o/r",
        "gh pr list --repo=2130706433/o/r",
        "gh issue list -R git@evil.example:o/secret",
        "gh issue list -R git@evil.example/o:secret",
        "gh repo view git@evil.example/o:r",
        "gh api https://evil.example/user",
        "gh pr view https://github.com@evil.example/o/r/pull/1",
    ])
    func ghReadOnAnotherHostAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a gh read naming a repository on this host still passes", arguments: [
        "gh repo view o/r",
        "gh issue list -R o/r",
        "gh pr view 1 --repo=o/r",
        "gh api repos/o/r/contents/a.b/c",
        "gh repo view github.com/o/r",
        "gh issue list -R github.com/o/r",
        "gh pr view https://github.com/o/r/pull/1",
        "gh issue view https://github.com/o/r/issues/2",
        "gh pr view v1.2/fix/x",
        "gh repo view o/r --branch feature/team/x",
        "gh issue list -R git@github.com:o/r",
        "gh pr list --search review-requested:@me",
    ])
    func ghReadOnThisHostPasses(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("a merge or a checkout through gh stays refused", arguments: [
        "gh pr merge 1", "gh pr checkout 1", "gh pr -R o/r merge 1",
    ])
    func ghBranchChangeRefused(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .refused)
    }

    @Test("a gh command that waits on what it follows stays with the owner", arguments: [
        "gh run watch 1", "gh pr checks 1 --watch", "gh pr checks 1 --interval 5", "gh pr checks 1 --watch=true",
    ])
    func ghWaitingAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("every gh read the read list answers is a read here too", arguments: [
        "gh pr view 1", "gh pr list", "gh pr diff 1", "gh pr checks 1", "gh pr status", "gh issue view 1",
        "gh issue list", "gh issue status", "gh run view 1", "gh run list", "gh release view v1", "gh release list",
        "gh workflow view test.yml", "gh workflow list",
    ])
    func readListGhVerbsPass(_ command: String) {
        let words = command.split(separator: " ").map(String.init)
        #expect(OrchestratorReadList.contains(words))
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }
}

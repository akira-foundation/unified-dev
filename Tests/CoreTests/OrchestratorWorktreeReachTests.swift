import Foundation
import Testing
@testable import Core

@Suite("Reads without asking stay inside the worktree")
struct OrchestratorWorktreeReachTests {
    struct Fixture {
        let worktree: String
        let outside: String

        init() throws {
            let scratch = TestScratch.unique("reach")
            worktree = scratch + "/worktree"
            outside = scratch + "/outside"
            let files = FileManager.default
            for directory in [worktree + "/src", worktree + "/trap", worktree + "/clean/deeper", outside] {
                try files.createDirectory(atPath: directory, withIntermediateDirectories: true)
            }
            try "secret".write(toFile: outside + "/secret.txt", atomically: true, encoding: .utf8)
            for file in ["README.md", "src/a.txt", "clean/deeper/b.txt"] {
                try "x".write(toFile: worktree + "/" + file, atomically: true, encoding: .utf8)
            }
            try files.createSymbolicLink(atPath: worktree + "/inner-link", withDestinationPath: "src/a.txt")
            try files.createSymbolicLink(atPath: worktree + "/out-link", withDestinationPath: outside + "/secret.txt")
            try files.createSymbolicLink(atPath: worktree + "/trap/way-out", withDestinationPath: outside)
        }

        func answers(_ command: String) -> Bool {
            OrchestratorToolGuard.answersItself(
                toolName: "Bash", input: .object(["command": .string(command)]), worktree: worktree, runsUnasked: true
            )
        }

        func verdict(_ command: String) -> OrchestratorUnaskedVerdict {
            OrchestratorWorktreeReach.verdict(command, worktree: worktree)
        }
    }

    @Test("a read of a path inside the worktree passes", arguments: [
        "cat README.md", "cat src/a.txt", "cat ./src/../README.md", "cat inner-link", "ls", "ls src", "rg x src",
        "head -n 5 README.md", "cat src/*.txt", "cd ./src && cat a.txt", "cd ./clean && ls deeper", "git show HEAD:README.md",
        "git log -1", "sed -n '/x/p' README.md", "echo \"$(git status)\"", "gh api /repos/o/r/pulls",
        "gh pr view https://github.com/o/r/pull/1", "wc -l README.md src/a.txt", "rg -g '*.swift' x", "grep -rn x src",
        "rg \"count == 0\" src", "rg \"// TODO\" src", "grep -n \"=>\" README.md", "ls -d .*", "rg 'let .* = ' src",
        "git log --oneline | awk '{print $1}'", "rg 'return nil$' src", "gh api /repos/o/r/pulls --paginate",
        "rg -e /api src", "rg --glob=*.swift x src", "grep --color=never -n x README.md", "sed -e '/x/p' README.md", "for i in 1 2; do cd .; done; ls",
    ])
    func insidePasses(_ command: String) throws {
        let fixture = try Fixture()
        #expect(fixture.verdict(command) == .passes)
        #expect(fixture.answers(command))
    }

    @Test("an absolute path inside the worktree passes")
    func absoluteInsidePasses() throws {
        let fixture = try Fixture()
        #expect(fixture.answers("cat \(fixture.worktree)/README.md"))
        #expect(fixture.answers("cd \(fixture.worktree)/src && cat a.txt"))
        let resolved = WorktreePathResolver(worktree: fixture.worktree).root
        #expect(OrchestratorToolGuard.answersItself(
            toolName: "Shell", input: .object(["command": .string("ls"), "cwd": .string(resolved)]),
            worktree: fixture.worktree, runsUnasked: true
        ))
    }

    @Test("a read that names a path outside the worktree asks", arguments: [
        "cat ../x", "cat ~/.ssh/id_rsa", "cat ~", "cat ~root/x", "ls /", "cat /etc/hosts", "cat < /etc/hosts",
        "cat </etc/hosts", "rg --ignore-file=/etc/hosts y", "grep -f/etc/hosts x", "grep -f ../x y",
        "tar -tf /tmp/x.tar", "git log -- /etc", "git show HEAD:../x", "diff README.md /etc/hosts",
        "jq -n 'include \"/etc/x\"; 1'", "head -n1 file:///etc/hosts", "cat =ls", "realpath ..", "stat ~/.zshrc",
        "sed --expression=p /etc/hosts", "sed --expression=p ~/x", "sed -n p ../x", "grep -f /etc/hosts x",
        "rg --ignore-file /etc/hosts x", "grep -e x /etc/hosts", "rg -- x /etc/hosts",
        "grep --regexp=. /etc/hosts", "rg --regexp=. /etc", "grep --file=README.md ~/.zshrc", "grep --reg=x -- /etc/hosts",
        "grep -ex /etc/hosts", "grep -fREADME.md /etc/hosts",
    ])
    func outsideAsks(_ command: String) throws {
        let fixture = try Fixture()
        #expect(fixture.verdict(command) == .asks)
        #expect(!fixture.answers(command))
    }

    @Test("a link inside the worktree is judged by where it really leads", arguments: [
        "cat out-link", "cat *", "cat [o]ut-link", "cat o?t-link", "cat trap/way-out/secret.txt", "ls trap/way-out",
        "head out-link", "wc -c ./src/../out-link",
    ])
    func linkOutAsks(_ command: String) throws {
        let fixture = try Fixture()
        #expect(fixture.verdict(command) == .asks)
        #expect(!fixture.answers(command))
    }

    @Test("a change of directory passes only into a directory with no way out below it", arguments: [
        "cd .. && cat x", "cd", "cd -", "cd /tmp && ls", "cd ~ && ls", "cd ./trap && ls", "cd ./trap", "pushd ./trap",
        "popd", "cd $HOME && ls", "builtin cd ..", "cd src && ls", "cd ./src ./clean && ls", "cd ./missing && ls",
        "cd +1", "cd ./README.md",
    ])
    func directoryChangeOutAsks(_ command: String) throws {
        let fixture = try Fixture()
        #expect(fixture.verdict(command) == .asks)
    }

    @Test("a nested shell, an expansion or a fed list cannot carry a path past the limit", arguments: [
        "sh -c 'cat /etc/hosts'", "bash -c \"cat \\/etc/hosts\"", "sh -c 'cd .. && cat x'", "cat $(echo x)",
        "cat $HOME/x", "cat \"$HOME\"/x", "ls | xargs cat", "find . -type l -exec cat {} ;", "find -L . -name x",
        "rg -L x", "rg --follow x", "grep -R x .", "tree -l", "ls -LR", "du -L", "diff -r src clean",
        "for f in *; do cat \"$f\"; done", "echo $HOME/*", "printf '%s' $PWD/../*", "shasum -c sums.txt",
        "cksum --check sums.txt", "find -H . -name x", "find . -follow", "grep -S x .", "ls --dereference x",
        "egrep -R x .",
    ])
    func indirectionAsks(_ command: String) throws {
        let fixture = try Fixture()
        #expect(fixture.verdict(command) == .asks)
    }

    @Test("gh and git reading a local file outside the worktree ask", arguments: [
        "gh api repos/o/r --input /etc/hosts", "gh api -F body=@/etc/hosts repos/o/r", "gh api -F body=@../x repos/o/r",
        "gh pr view 1 --template \"$(cat /etc/hosts)\"", "git -C /tmp status", "git show HEAD -- /etc/hosts",
        "git diff --no-index README.md /etc/hosts", "git grep -f /etc/hosts", "git log -- ../x", "git diff HEAD -- ~/.zshrc",
    ])
    func ghAndGitOutsideAsk(_ command: String) throws {
        let fixture = try Fixture()
        #expect(fixture.verdict(command) == .asks)
        #expect(!fixture.answers(command))
    }

    @Test("the always-on read list keeps to the worktree too")
    func readListFollowsLinks() throws {
        let fixture = try Fixture()
        #expect(!OrchestratorToolGuard.answersItself(
            toolName: "Bash", input: .object(["command": .string("cat out-link")]), worktree: fixture.worktree
        ))
        #expect(OrchestratorToolGuard.answersItself(
            toolName: "Bash", input: .object(["command": .string("cat README.md")]), worktree: fixture.worktree
        ))
    }

    @Test("the orchestrator's Claude goes back to the worktree after every command")
    func claudeKeepsTheWorktree() {
        let settings = AgentRunner.settingsJSON(outputStyle: nil, orchestrates: true) ?? ""
        #expect(JSONValue.parse(settings)?["env"]?["CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR"] == .string("1"))
        #expect(JSONValue.parse(AgentRunner.settingsJSON(outputStyle: nil, guardsCrossing: true) ?? "")?["env"] == nil)
    }
}

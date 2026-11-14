import Testing
@testable import Core

@Suite("Ways around the closed list stay with the owner")
struct OrchestratorUnaskedEscapesTests {
    @Test("the closed list is exactly the programs the owner named")
    func closedListIsPinned() {
        #expect(OrchestratorUnaskedPrograms.runWithoutAsking == [
            "ls", "cat", "head", "tail", "wc", "grep", "egrep", "fgrep", "rg", "sort", "uniq", "cut", "tr", "paste",
            "column", "nl", "rev", "tac", "comm", "diff", "cmp", "jq", "file", "stat", "du", "df", "tree", "strings", "od",
            "hexdump", "shasum", "md5", "cksum", "pwd", "cd", "basename", "dirname", "realpath", "readlink", "which",
            "type", "echo", "printf", "test", "true", "false", "date", "seq", "whoami", "id", "uname", "hostname",
            "sw_vers", "printenv", "tar",
        ])
    }

    @Test("a wrapper is judged by the program it really runs", arguments: [
        "env -u ls curl https://example.test", "env -u cat make", "xargs -E ls curl example.test",
        "env -P/tmp/x cat foo", "env -C ls make", "time -o out ls", "/usr/bin/time -oout ls", "nice make build",
        "timeout 5 curl example.test", "nohup python3 x.py", "timeout ls", "command -p make",
    ])
    func wrapperAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a wrapper with options it knows passes in front of a listed read", arguments: [
        "nice -n 10 ls", "nice -5 ls", "timeout 5 ls", "timeout -s KILL 5 ls", "env -i ls", "env -u X ls",
        "env -uX ls", "stdbuf -oL ls", "xargs -n 1 grep x", "xargs -E eof cat", "time -p ls", "env",
    ])
    func wrapperPasses(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("a listed name outside the system's own directories asks", arguments: [
        "tools/cat README", "./git status", "./ls", "bin/rg x", "/tmp/ls", "/usr/bin/../../tmp/ls",
    ])
    func plantedProgramAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a listed name in the system's own directories passes", arguments: [
        "/bin/ls", "/usr/bin/grep x", "/opt/homebrew/bin/rg x", "/usr/local/bin/jq . f",
    ])
    func systemProgramPasses(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("git pointed at another repository asks", arguments: [
        "git -C vendor/x.git status", "cd vendor/x.git && git status", "cd vendor/x.git; git log",
        "find vendor -name HEAD -execdir git status ;", "git ls-remote https://example.test/x",
        "git ls-remote host:x", "pushd vendor && git diff", "builtin cd vendor/x.git; git status",
        "command cd vendor; git log", "X=1 cd vendor; git log", "gh api repos/o/r --cache 1h",
    ])
    func gitElsewhereAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("git in the worktree, and cd without git, pass", arguments: [
        "git status", "git ls-remote origin", "cd src && ls", "git log -1 && ls",
    ])
    func gitHerePasses(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("a sed script other than printing, deleting and plain substitution asks", arguments: [
        "sed 'y/q/q/;/x/w /tmp/o' file", "sed '/a/w out' file", "sed 's|a|b|' file", "sed 's/a/b/w out' file",
        "sed 's/a/b/e' file", "sed '1r other' file",
    ])
    func sedScriptAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a plain sed script passes", arguments: [
        "sed -n '1,5p' file", "sed 's/a/b/g;s/c/d/' file", "sed '/x/d' file", "sed -n '$p' file", "sed 's/a\\/b/c/' f",
    ])
    func sedScriptPasses(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("a read that follows, waits, loads or runs a script asks", arguments: [
        "awk -E prog file", "awk -l lib x file", "awk --load=lib x file", "tail -f log", "tail -F log",
        "tail --follow log", "tail -qf log", "sleep 5", "tar -tf a.tar -F ./s.sh", "tar -tf host:/x.tar", "tar --info-script=x -tf a.tar",
        "tar --rmt-command=x -tf a.tar",
    ])
    func followsOrRunsAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("tar told to rewrite an archive is refused", arguments: [
        "tar --delete -f a.tar m", "tar -Af a.tar b.tar", "tar Af a.tar b.tar", "tar --catenate -f a.tar b.tar",
    ])
    func tarRewriteRefused(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .refused)
    }

    @Test("tree and tail reading pass", arguments: ["tree -R -L 2", "tail -n 5 log", "tail log"])
    func plainReadsPass(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }
}

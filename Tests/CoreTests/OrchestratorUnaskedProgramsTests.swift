import Testing
@testable import Core

@Suite("Programs the orchestrator's judge knows by name")
struct OrchestratorUnaskedProgramsTests {
    @Test("a program that writes files is refused", arguments: [
        "tee", "cp", "mv", "rm", "rmdir", "mkdir", "touch", "ln", "chmod", "chown", "chgrp", "truncate", "patch",
        "install", "rsync", "dd", "shred", "unlink", "ditto", "mkfifo", "vi", "vim", "nvim", "ed", "ex", "emacs", "nano",
        "wget", "scp", "unzip", "gzip", "gunzip", "bzip2", "bunzip2", "xz", "unxz",
    ])
    func fileWriter(_ program: String) {
        #expect(OrchestratorUnaskedJudge.verdict("\(program) file") == .refused)
    }

    @Test("a program writing through a flag is refused", arguments: [
        "curl -o file example.test", "curl -sSLo file example.test", "curl -O example.test",
        "curl --output file example.test", "sort -o file file", "tar -xf archive", "tar xf archive",
        "find . -fprint file", "find . -fls file", "eval -- 'rm x'", "trap -- 'rm x' EXIT", "find . -exec ls {} + -delete", "tar -C . -xf archive", "curl --outp file example.test",
        "sed -I '' 's/a/b/' file", "gh pr checkout 1", "gh pr -R o/r checkout 1", "gh pr -R a/b -R a/b merge 1",
    ])
    func writesThroughAFlag(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .refused)
    }

    @Test("the same programs read without a card", arguments: [
        "sort file", "tar tf archive", "git fetch origin", "git fetch origin develop",
        "sed -n '$p' src/main.rs", "sed -e 's/a/b/' web.txt", "awk '{print $1}' file", "ls \"$HOME\"", "[ -f file ]",
        "[[ -n a ]]", "find . -name x -exec ls {} +", "bash -lc 'ls'", "echo \"$(git log)\"", "sed -n '1,5p' file", "sed 's/a/w/' file", "sed 's/a/b/g' file", "tar -tf x.tar",
        "git log --oneline", "git log --no-merges", "gh pr view 1", "gh issue list",
    ])
    func stillPasses(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("a program that runs another has what it runs judged", arguments: [
        "env", "sudo", "doas", "command", "builtin", "exec", "nohup", "time", "nice", "ionice", "timeout", "gtimeout",
        "caffeinate", "stdbuf", "script", "flock", "lockf", "arch", "setsid", "unbuffer", "xargs", "parallel", "watch",
        "fd", "tmux", "screen", "ssh", "xcrun", "busybox", "direnv", "mise", "asdf", "noglob", "nocorrect", "-",
        "repeat", "coproc", "ifne", "chronic", "uv", "uvx", "bundle", "poetry", "pipenv", "pipx", "pnpm", "npm", "npx",
        "bunx", "yarn", "devbox", "nix", "nix-shell", "conda", "rye", "hatch", "pdm", "rtk",
    ])
    func runner(_ program: String) {
        #expect(OrchestratorUnaskedJudge.verdict("\(program) git commit -m x") == .refused)
        #expect(OrchestratorUnaskedJudge.verdict("\(program) 'git commit -m x'") == .refused)
    }

    @Test("a shell has its script judged, whichever shell it is", arguments: [
        "sh", "bash", "zsh", "dash", "fish", "ksh", "mksh", "tcsh", "csh", "ash", "rbash", "pwsh", "nu", "xonsh",
    ])
    func shell(_ program: String) {
        #expect(OrchestratorUnaskedJudge.verdict("\(program) -c 'git commit -m x'") == .refused)
        #expect(OrchestratorUnaskedJudge.verdict("\(program) -c 'ls | wc -l'") == .passes)
        #expect(OrchestratorUnaskedJudge.verdict(program) == .asks)
    }

    @Test("what stays with the owner stays there", arguments: [
        "echo x | bash -s y",
        "echo x | sh -",
        "python3 -W ignore -c 'x'",
        "osascript -l AppleScript -e 'x'",
        "echo x | python3 - y",
        "swift -e 'x'",
        "sqlite3 file 'select 1'",
        "defaults write some.domain key value",
        "security find-generic-password -w",
        "kill 1",
        "killall Finder",
        "pkill x",
        "launchctl list",
        "open .",
        "export X=1",
        "declare -x X=1",
        "typeset -x X=1",
        "readonly X=1",
        "set -a",
        "FOO=1 make build",
        "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=a GIT_CONFIG_VALUE_0=b git status",
        "GIT_SSH_COMMAND=x git fetch",
        "BASH_ENV=file bash -c 'true'",
        "PATH=/x git log",
        "PATH=/x; git log",
        "env GIT_EXTERNAL_DIFF=x git diff",
        "env /usr/bin/g?t status",
        "env =git status",
        "env ~/bin/git status",
        "env -S\"ls -a\"",
        "find . -exec g?t status \\;",
        "find . -exec",
        "sed -n 'w file' other",
        "sed -n '/a/w file' other",
        "sed '1e ls' other",
        "sed 's/a/b/e' other",
        "sed -f script other",
        "git -c a=b status",
        "git --config-env=a=b status",
        "git --exec-path=x status",
        "git --git-dir=x status",
        "git --git-dir x status",
        "git --work-tree=x status",
        "git --namespace=x status",
        "git diff --output=file",
        "git diff --ext-diff",
        "git log --exec=x",
        "git grep -O x",
        "git grep --open-files-in-pager=x y",
        "git fetch --upload-pack=x",
        "git ls-remote --receive-pack=x",
        "git diff --no-index a b",
        "git fetch origin +a:a",
        "git fetch --prune",
        "git fetch -u origin a:a",
        "git grep --open=x y",
        "env -Sls",
        "git grep -nOx y",
        "sed -n 's a b gw out' file",
        "[[ 1 -eq y ]]",
        "`echo git` push",
        "gi`echo`t push",
        "find . `echo -delete`",
        "x=-delete; find . $x",
        "find . \"$x\"",
        "((1<<x))\ngit push\nx",
        "echo $\\\n'\\'' ; git push ; echo '\\'",
        "echo \"$\\\n(git push)\"",
        "echo x | bash -O extglob",
        "echo x | zsh -o nullglob",
        "echo x | bash --rcfile y",
        "echo x | bash +O extglob",
        "echo x | python3 -W ignore",
        "echo x | perl -I y",
        "sed -n 'sxaxbxw out' file",
        "sed -l 5 'w out' file",
        "gi{t..t} push",
        "{gi,}t push",
        "[[ 'a[$(ls)]' -eq 0 ]]",
        "[[ $x -eq 0 ]]",
        "if [[ -n a ]] ls",
        "echo *(e+ls+)",
        "emulate zsh -c 'ls'",
        "let 'a[$(ls)]'",
        "printf -v x y",
        "test -v x",
        "git ls-remote --upload=x .",
        "git fetch --pru",
        "echo x | xargs -I y sh -c y",
        "echo x | xargs -I y y file",
        "echo x | xargs sh",
        "echo x | parallel",
        "echo x | sh /dev/stdin",
        "echo x | bash /dev/fd/0",
        "echo x | python3 /dev/stdin",
        "python3 <<< x",
        "sed 's/a/b/gw out' file",
        "sed -n '1!w out' file",
        "sed -n 'wout' file",
        "sed 's|a|b|w out' file",
        "sed --expression='w out' file",
        "gh repo clone o/r",
        "gh issue -R o/r delete 1",
        "gh auth token",
        "gh secret set x",
        "gh alias set x y",
        "gh extension install x",
        "gh m 1",
        "gh browse",
        "gh repo delete x --yes",
        "gh release delete x",
        "gh issue delete 1",
        "gh repo archive x",
        "gh -R o/r pr view 1",
        "gh --repo o/r api x",
        "gh api --method POST x",
        "gh api x \"$y\"",
        "gh api -f a=b x",
        "gh api -F a=b x",
        "gh api --field a=b x",
        "gh api --raw-field a=b x",
        "gh api --input file x",
    ])
    func staysWithTheOwner(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a command hidden from the first reading does not pass", arguments: [
        "echo `echo \\`rm -rf Sources\\` `",
        "echo $[1<<x]\ngit push\nx",
    ])
    func hiddenCommand(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) != .passes)
    }

    @Test("a flag in front of the subcommand does not hide a merge or a verb", arguments: [
        "gh -R o/r pr merge 1", "gh --repo o/r pr merge 1", "gh pr -R o/r merge 1", "git -C dir commit -m x",
    ])
    func flagInFront(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .refused)
    }

    @Test("a hostile command costs a bounded amount of work and stays with the owner or is refused")
    func boundedWork() {
        let runners = String(repeating: "env eval ", count: 400) + "ls"
        #expect(OrchestratorUnaskedJudge.verdict(runners) >= .asks)
        var nested = "ls"
        for _ in 0..<400 { nested = "echo \"$(\(nested))\"" }
        #expect(OrchestratorUnaskedJudge.verdict(nested) == .asks)
        var ticks = "ls"
        for _ in 0..<8 { ticks = "echo \"`\(ticks.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`"))`\"" }
        #expect(OrchestratorUnaskedJudge.verdict(ticks) == .passes)
    }

    @Test("a reserved word at the head of a clause is skipped and the command after it is judged", arguments: [
        "if git push; then ls; fi", "if true; then ls; elif git push; fi", "while git push; do ls; done",
    ])
    func reservedWordsAreSkipped(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .refused)
    }

    @Test("a program whose name only ends like a reserved word is the program", arguments: [
        "exif rm x", "motif rm x", "./if rm x", "gif git push",
    ])
    func endingLikeAReservedWordIsAProgram(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a program on the closed list runs without asking", arguments: OrchestratorUnaskedPrograms.runWithoutAsking.sorted())
    func closedListPasses(_ program: String) {
        #expect(OrchestratorUnaskedJudge.verdict("\(program) file") == .passes)
        #expect(OrchestratorUnaskedJudge.verdict("/usr/bin/\(program) file") == .passes)
    }

    @Test("a program off the closed list asks rather than being refused", arguments: [
        "make build", "swift build -c release", "swift test", "xcodebuild -list", "./Tools/test-core.sh Filter",
        "python3 tool.py", "python3 -m json.tool file", "node x.js", "ruby x.rb", "perl x.pl", "curl -s example.test",
        "curl -d @file example.test", "bun run build", "cargo build", "docker ps", "exif x", "less file", "base64 -o x y",
    ])
    func offTheListAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a wrapper that adds nothing is judged by what it runs", arguments: [
        "env ls", "time ls", "nice ls", "timeout 5 ls", "nohup ls", "command ls", "builtin cd x", "xargs ls",
        "noglob ls", "stdbuf -o0 ls", "gtimeout 5 ls", "nocorrect ls",
    ])
    func plainWrapperPasses(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("a runner that does more than wrap asks even for a listed program, and a refusal inside still refuses", arguments: [
        "ssh", "npx", "bunx", "npm", "watch", "tmux", "xcrun", "sudo", "parallel", "uvx", "nix",
    ])
    func runnerThatAddsSomethingAsks(_ runner: String) {
        #expect(OrchestratorUnaskedJudge.verdict("\(runner) ls") == .asks)
        #expect(OrchestratorUnaskedJudge.verdict("\(runner) git push") == .refused)
    }

    @Test("a reserved word that closes a compound, or opens a loop, passes", arguments: [
        "for f in a b; do echo \"$f\"; done", "if true; then ls; fi", "while true; do ls; done",
    ])
    func compoundWordsPass(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("a word that closes a compound followed by more is a program", arguments: ["fi x", "done x", "esac x"])
    func closerWithWordsAsks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }
}

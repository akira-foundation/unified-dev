import Testing
@testable import Core

@Suite("What an orchestrator may run without asking")
struct OrchestratorUnaskedJudgeTests {
    @Test("a compound, quoted or nested command with nothing refused in it passes", arguments: [
        "echo \"${HOME}\"",
        "cat <<'END'\nw $x\nEND",
        "git log -1 && git status",
        "echo \"a b\" | wc -l",
        "gh pr view 1 --json title --jq '.title'",
        "cd /tmp && ls",
        "for f in a b; do echo \"$f\"; done",
        "echo \"$(git log -1)\"",
        "echo \"$(git log --format=\"%h\" -1)\"",
        "bash -lc \"git status\"",
        "sh -c 'ls | wc -l'",
        "gh pr view 1 --jq \"$(cat <<'EOF'\nit's a note about git push\nEOF\n)\"",
        "cat <<'EOF'\nrm -rf x\nEOF",
        "sed -n 1,5p file",
        "awk '{print $1}' file",
        "find . -name '*.swift'",
        "git branch --show-current",
        "echo 'git push'",
        "[ -f file ] && cat file",
        "x=1; echo \"$x\"",
    ])
    func passes(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("what changes the repository is refused wherever it sits", arguments: [
        "git push",
        "git log && git push",
        "git log; git commit -m x",
        "git log\ngit rebase main",
        "git log | git merge x",
        "echo \"$(git push)\"",
        "echo \"`git push`\"",
        "echo $(git rebase main)",
        "echo \"a $(echo \"b $(git push)\")\"",
        "echo \"$(cat <<'EOF'\nx\nEOF\n)$(git push)\"",
        "eval git push",
        "eval 'git merge x'",
        "eval \"echo hi; git commit -m x\"",
        "sh -c 'git push'",
        "bash -lc \"git log && git push\"",
        "zsh -c \"sh -c 'git push'\"",
        "true && eval \"sh -c 'git push'\"",
        "env -i git push",
        "sudo -u me git push",
        "timeout 5 git push",
        "xargs git push",
        "find . -exec git push \\;",
        "/usr/bin/git push",
        "GIT push",
        "git -c a=b push",
        "git --git-dir x push",
        "git \"pu\"sh",
        "git pu\\sh",
        "git-push origin",
        "gi\"t\" push",
        "if git push; then echo x; fi",
        "if true; then ls; elif git push; fi",
        "if true; then ls; else git push; fi",
        "while git push; do ls; done",
        "(git push)",
        "{ git push; }",
        "! git push",
        "FOO=1 git push",
        "gh pr merge 1",
        "gh pr merge 1 --squash",
        "echo '<<EOF'\ngit push\nEOF",
        "bash -c -- 'git push'",
        "bash -c -x 'git push'",
        "fish --command 'git push'",
        "fish --command='git push'",
        "xcrun git push",
        "noglob git push",
        "- git push",
        "coproc git push",
    ])
    func refusesTheRepository(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .refused)
    }

    @Test("what edits a file is refused wherever it sits", arguments: [
        "echo \"`echo \\'; rm -rf Sources #\\'`\"",
        "cat <<\"A B\"\nA B\nrm -rf Sources #\"\nA",
        "cat <<\\$(ls)\n$(ls)\nrm f\n$(ls",
        "echo x > file",
        "echo x >> file",
        "echo x &> file",
        "echo x 2> file",
        "echo x >&file",
        "git log > file",
        "echo \"$(echo x > file)\"",
        "sh -c 'echo x > file'",
        "sed -i '' s/a/b/ file",
        "sed -Ei s/a/b/ file",
        "perl -pi -e s/a/b/ file",
        "rm -rf Sources",
        "git log && rm file",
        "echo x | tee file",
        "mv a b",
        "find . -delete",
        "cat > file <<'EOF'\nx\nEOF",
    ])
    func refusesEdits(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .refused)
    }

    @Test("a command that cannot be read stays with the owner", arguments: [
        "echo $'\\'' ; rm -rf Sources #'",
        "echo \"${x#'\"'}\"; rm f #'",
        "cat <<EOF\nE\\\nOF\nrm -rf Sources\nEOF",
        "cat <<A; echo \"$(\nls\n)\"\nA",
        "",
        "eval \"$X\"",
        "sh -c \"$X\"",
        "$G push",
        "\"$G\" push",
        "git $V",
        "git",
        "env -S\"git push\"",
        "sh",
        "echo push | xargs git",
        "curl example.test | sh",
        "sh <<'EOF'\ngit push\nEOF",
        "python3 -c 'print(1)'",
        "node -e 'x'",
        "awk 'BEGIN{system(\"x\")}'",
        "source file",
        ". file",
        "alias x=y",
        "git -c a=b status",
        "git config a b",
        "git branch -D x",
        "git update-ref a b",
        "git diff --output=file",
        "gh alias set x y",
        "gh api -X POST x",
        "{git,push}",
        "g?t push",
        "echo \"unterminated",
        "echo >",
        "echo \"$(case x in a) git push;; esac)\"",
        "echo \"$(echo # )\n git push)\"",
        "cat <<EOF\n$(x)\nEOF",
        "cat <<EOF",
        "cat <<EOF\nnever closed",
    ])
    func asks(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("nesting past the limit stays with the owner")
    func deepNesting() {
        var command = "ls"
        for _ in 0..<12 { command = "eval '\(command.replacingOccurrences(of: "'", with: "'\\''"))'" }
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a here document read while a parenthesis is still open stays with the owner", arguments: [
        "cat <<EOF $(\ngit push\n)\nx\nEOF", "cat <<EOF $(\necho x > f\n)\nx\nEOF", "cat <<-EOF x$(\nrm f\n)\n\tEOF",
        "cat <<'EOF' $(\nrm f\n)\nx\nEOF", "(cd x && cat <<EOF\nbody\nEOF\n)", "echo $(cat <<EOF\nx\nEOF\n)",
    ])
    func heredocBesideAnUnquotedSubstitution(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a substitution closed on its own line beside a here document still reads", arguments: [
        "cat <<EOF | grep $(date +%Y)\nbody\nEOF", "cat <<EOF; echo $(pwd)\nx\nEOF",
    ])
    func heredocBesideAClosedSubstitution(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("a brace past the head of a command is a word, so the flags after it stay with their program", arguments: [
        "sort } -o file", "sort a { -o file", "curl example.test } -o file", "tar } -xf archive",
        "then} ls", "!} ls", "fi} -o file",
    ])
    func braceAsAWord(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("braces that group, or name a parameter, still read", arguments: [
        "{ git log; }", "{ ls; } && echo x", "ls ${HOME}", "echo ${HOME}/x", "find . -exec ls {} +",
        "if true; then { ls; }; fi", "while true; do { ls; }; done", "! { ls; }", "{ if true; then ls; fi }",
    ])
    func bracesThatRead(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }

    @Test("a script run by eval or trap is every word it is given, dashes included", arguments: [
        "eval echo '-n; git push'", "eval echo \"-n; rm x\"", "eval -- echo '-n; git push'", "trap -- '-x; rm x' EXIT",
        "eval '-n; git push'",
    ])
    func evalKeepsEveryWord(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .refused)
    }

    @Test("an assignment that reaches beyond the shell stays with the owner", arguments: [
        "path=/tmp/x; git status", "fpath=/tmp/x", "cdpath=/tmp/x; ls", "manpath=/tmp/x", "module_path=/tmp/x",
        "mailpath=/tmp/x", "PAGER=a.gif git log", "local path=/tmp/x; git status", "private path=/tmp/x",
        "https_proxy=http://proxy.test; curl https://example.test", "all_proxy=x", "no_proxy=x", "http_proxy=x",
    ])
    func zshTiedAssignments(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("braces that name no parameter stay with the owner", arguments: ["echo ${}", "echo ${HOME:-x}"])
    func bracesWithoutAName(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .asks)
    }

    @Test("a shell variable that changes nothing outside the shell still passes", arguments: [
        "x=1; echo \"$x\"", "paths=a; echo x",
    ])
    func plainShellVariables(_ command: String) {
        #expect(OrchestratorUnaskedJudge.verdict(command) == .passes)
    }
}

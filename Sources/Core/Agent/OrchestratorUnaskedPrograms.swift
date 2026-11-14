import Foundation

enum OrchestratorUnaskedPrograms {
    typealias Verdict = OrchestratorUnaskedVerdict

    static let simpleWord = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./+-")
    static let tests: Set<String> = ["[", "[["]
    static let shells: Set<String> = [
        "sh", "bash", "zsh", "dash", "fish", "ksh", "mksh", "tcsh", "csh", "ash", "rbash", "pwsh", "nu", "xonsh",
    ]
    static let scripted: Set<String> = ["eval", "trap"]
    static let leftWithTheOwner: Set<String> = [
        "alias", "source", ".", "fc", "function", "case", "bind", "autoload", "export", "declare", "typeset", "readonly",
        "set", "setopt", "unsetopt", "shopt", "sqlite3", "defaults", "security", "kill", "killall", "pkill", "launchctl",
        "open", "let", "read", "unset", "getopts", "emulate", "zmodload", "zpty", "sched", "vared", "zcompile", "enable",
        "disable", "hash", "mapfile", "readarray", "local", "private", "integer", "float",
    ]
    static let runners: Set<String> = [
        "env", "sudo", "doas", "command", "builtin", "exec", "nohup", "time", "nice", "ionice", "timeout", "gtimeout",
        "caffeinate", "stdbuf", "script", "flock", "lockf", "arch", "setsid", "unbuffer", "xargs", "parallel", "watch",
        "fd", "tmux", "screen", "ssh", "xcrun", "busybox", "direnv", "mise", "asdf", "noglob", "nocorrect", "-",
        "repeat", "coproc", "ifne", "chronic", "uv", "uvx", "bundle", "poetry", "pipenv", "pipx", "pnpm", "npm", "npx",
        "bunx", "yarn", "devbox", "nix", "nix-shell", "conda", "rye", "hatch", "pdm", "rtk",
    ]
    static let runWithoutAsking: Set<String> = [
        "ls", "cat", "head", "tail", "wc", "grep", "egrep", "fgrep", "rg", "sort", "uniq", "cut", "tr", "paste",
        "column", "nl", "rev", "tac", "comm", "diff", "cmp", "jq", "file", "stat", "du", "df", "tree", "strings", "od",
        "hexdump", "shasum", "md5", "cksum", "pwd", "cd", "basename", "dirname", "realpath", "readlink", "which", "type",
        "echo", "printf", "test", "true", "false", "date", "seq", "whoami", "id", "uname", "hostname", "sw_vers",
        "printenv", "tar",
    ]
    static let steeredByTheirArguments: Set<String> = ["sort", "uniq", "tree", "file", "rg", "tar", "date", "hostname"]
    static let findWriters = ["-delete", "-fprint", "-fls"]
    static let findRunners: Set<String> = ["-exec", "-execdir", "-ok", "-okdir"]

    private static let systemDirectories: Set<String> = [
        "/bin", "/usr/bin", "/sbin", "/usr/sbin", "/usr/local/bin", "/opt/homebrew/bin",
    ]
    private static let directoryChangers: Set<String> = ["cd", "pushd", "popd", "chdir"]
    private static let keywords: Set<String> = ["if", "elif", "then", "else", "do", "while", "until", "!"]
    private static let closers: Set<String> = ["fi", "done", "esac"]
    private static let fileWriters: Set<String> = [
        "tee", "cp", "mv", "rm", "rmdir", "mkdir", "touch", "ln", "chmod", "chown", "chgrp", "truncate", "patch",
        "install", "rsync", "dd", "shred", "unlink", "ditto", "mkfifo", "vi", "vim", "nvim", "ed", "ex", "emacs", "nano",
        "wget", "scp", "unzip", "gzip", "gunzip", "bzip2", "bunzip2", "xz", "unxz",
    ]
    private static let interpreters: Set<String> = [
        "python", "python2", "python3", "pypy", "pypy3", "node", "nodejs", "deno", "bun", "ruby", "perl", "php", "lua",
        "osascript", "tclsh", "expect", "swift",
    ]
    private static let arithmeticTests: Set<String> = ["-eq", "-ne", "-lt", "-le", "-gt", "-ge"]
    private static let decidedByWords: Set<String> = ["git", "find", "curl", "sort", "tar"]
    private static let assignsThroughAFlag: Set<String> = ["printf", "print", "test"]
    private static let curlWritingFlags = [
        "--output", "--remote-name", "--dump-header", "--cookie-jar", "--config", "--trace", "--libcurl", "--etag-save",
        "--stderr", "--hsts", "--alt-svc",
    ]
    private static let tarWritingFlags = [
        "--extract", "--get", "--create", "--append", "--update", "--use-compress", "--checkpoint-action", "--to-command",
        "--rsh", "--delete", "--catenate", "--concatenate",
    ]
    private static let flagsThatRunAProgram: [String: [String]] = [
        "sort": ["--compress-program"],
        "rg": ["--pre", "--hostname-bin"],
        "tail": ["--follow"],
        "tar": ["--info-script", "--new-volume-script", "--rmt-command", "--to-command", "--use-compress-program"],
    ]
    private static let reachesBeyondTheShell: Set<String> = [
        "path", "fpath", "cdpath", "manpath", "module_path", "mailpath", "http_proxy", "https_proxy", "ftp_proxy",
        "all_proxy", "no_proxy",
    ]
    private static let awks: Set<String> = ["awk", "gawk", "mawk", "nawk"]
    private static let seds: Set<String> = ["sed", "gsed"]

    static func name(of word: String) -> String {
        String(word.split(separator: "/").last ?? Substring(word)).lowercased()
    }

    static func isFoundOnTheSystemPath(_ word: String) -> Bool {
        guard let slash = word.lastIndex(of: "/") else { return true }
        return systemDirectories.contains(String(word[..<slash]))
    }

    static func changesDirectory(_ clause: [String]) -> Bool {
        clause.drop { isKeyword($0) || OrchestratorShellJudge.isAssignment($0) || ["builtin", "command"].contains($0) }
            .first.map { directoryChangers.contains(name(of: $0)) } == true
    }

    static func namesGit(_ word: String) -> Bool {
        let program = name(of: word)
        return program == "git" || program.hasPrefix("git-")
    }

    static func takesAnyArgumentsSafely(_ program: String) -> Bool {
        runWithoutAsking.contains(program) && !steeredByTheirArguments.contains(program)
    }

    static func isKeyword(_ word: String) -> Bool {
        keywords.contains(word)
    }

    static func staysInThisShell(_ assignment: String) -> Bool {
        let name = assignment.prefix { $0 != "=" }
        guard !reachesBeyondTheShell.contains(String(name)) else { return false }
        return name.allSatisfy { !$0.isUppercase }
    }

    static func keepsAScriptOutOfSight(_ argument: String) -> Bool {
        if argument.hasPrefix("/dev/") || argument.hasPrefix("/proc/") || argument.hasPrefix("+") { return true }
        guard argument.hasPrefix("-") else { return false }
        return !argument.contains(/^-[celux]+$/) && !["--login", "--"].contains(argument)
    }

    static func decidesByItsWords(_ word: String) -> Bool {
        let head = name(of: word)
        return decidedByWords.contains(head) || runners.contains(head) || shells.contains(head) || scripted.contains(head)
            || interpreters.contains(head) || awks.contains(head) || seds.contains(head)
    }

    static func isPlainTest(_ arguments: [String]) -> Bool {
        guard let last = arguments.last, ["]", "]]"].contains(last) else { return false }
        return arguments.dropLast().allSatisfy { word in !arithmeticTests.contains(word) && !word.contains { "$`[]".contains($0) } }
    }

    static func feedsItsInput(_ head: String, _ arguments: [String]) -> Bool {
        if head == "parallel" { return true }
        if head == "env" { return arguments.contains { $0.hasPrefix("-S") || names($0, oneOf: ["--split-string"]) } }
        guard head == "xargs" else { return false }
        return arguments.contains { word in
            shells.contains(name(of: word)) || scripted.contains(name(of: word))
                || word.hasPrefix("-I") || word.hasPrefix("-J") || word.hasPrefix("-i") || word.hasPrefix("--replace")
        }
    }

    static func verdict(of head: String, _ arguments: [String]) -> Verdict {
        if assignsThroughAFlag.contains(head), arguments.contains("-v") { return .asks }
        if fileWriters.contains(head) { return .refused }
        if interpreters.contains(head) { return interpreter(head, arguments) }
        if awks.contains(head) { return awk(arguments) }
        if seds.contains(head) { return sed(arguments) }
        if writesThroughAFlag(head, arguments) { return .refused }
        if runsThroughAFlag(head, arguments) { return .asks }
        if head == "for" || (closers.contains(head) && arguments.isEmpty) { return .passes }
        return runWithoutAsking.contains(head) ? .passes : .asks
    }

    private static func writesThroughAFlag(_ head: String, _ arguments: [String]) -> Bool {
        switch head {
        case "curl":
            arguments.contains { names($0, oneOf: curlWritingFlags) || hasShortFlag($0, in: "oODcK") }
        case "sort":
            arguments.contains { names($0, oneOf: ["--output"]) || hasShortFlag($0, in: "o") }
        case "uniq":
            operands(arguments, skippingValuesOf: "fs").count > 1
        case "tree":
            arguments.contains { names($0, oneOf: ["--output"]) || hasShortFlag($0, in: "o") }
                || (arguments.contains { hasShortFlag($0, in: "R") } && arguments.contains { hasShortFlag($0, in: "H") })
        case "file":
            arguments.contains { names($0, oneOf: ["--compile"]) || hasShortFlag($0, in: "C") }
        case "tar":
            arguments.contains { names($0, oneOf: tarWritingFlags) || hasShortFlag($0, in: "xcruAI") }
                || arguments.first.map { word in !word.hasPrefix("-") && word.contains { "xcruA".contains($0) } } == true
        default:
            false
        }
    }

    private static func runsThroughAFlag(_ head: String, _ arguments: [String]) -> Bool {
        guard let flags = flagsThatRunAProgram[head] else { return false }
        if head == "tar", arguments.contains(where: { $0.contains(":") || hasShortFlag($0, in: "FM") }) { return true }
        if head == "tail", arguments.contains(where: { hasShortFlag($0, in: "fF") }) { return true }
        return arguments.contains { names($0, oneOf: flags) }
    }

    private static func operands(_ arguments: [String], skippingValuesOf letters: String) -> [String] {
        var operands: [String] = []
        var words = arguments.makeIterator()
        while let word = words.next() {
            if word == "--" { return operands + Array(IteratorSequence(words)) }
            guard word.hasPrefix("-"), word != "-" else {
                operands.append(word)
                continue
            }
            let takesAValue = word.hasPrefix("--") ? !word.contains("=") && word.hasPrefix("--skip-")
                : word.last.map(letters.contains) == true
            if takesAValue { _ = words.next() }
        }
        return operands
    }

    static func names(_ word: String, oneOf flags: [String]) -> Bool {
        guard word.hasPrefix("--") else { return flags.contains { word.hasPrefix($0) } }
        let name = word.prefix { $0 != "=" }
        return name.count > 2 && flags.contains { $0.hasPrefix(name) || name.hasPrefix($0) }
    }

    static func hasShortFlag(_ word: String, in letters: String) -> Bool {
        word.hasPrefix("-") && !word.hasPrefix("--") && word.contains { letters.contains($0) }
    }

    private static func interpreter(_ head: String, _ arguments: [String]) -> Verdict {
        ["perl", "ruby"].contains(head) && arguments.contains(where: editsInPlace) ? .refused : .asks
    }

    private static func awk(_ arguments: [String]) -> Verdict {
        let isUnreadable = arguments.isEmpty || arguments.contains { word in
            ["-f", "--file", "-i", "--include", "-l", "--load", "-E", "--exec"].contains { word.hasPrefix($0) }
                || ["system", "getline", "|", ">", "@load", "@include"].contains { word.contains($0) }
        }
        return isUnreadable ? .asks : .passes
    }

    private static func sed(_ arguments: [String]) -> Verdict {
        if arguments.contains(where: { names($0, oneOf: ["--in-place"]) || hasShortFlag($0, in: "iI") }) { return .refused }
        guard let scripts = sedScripts(arguments), !scripts.isEmpty else { return .asks }
        return scripts.allSatisfy(isPlainSedScript) ? .passes : .asks
    }

    private static func sedScripts(_ arguments: [String]) -> [String]? {
        var scripts: [String] = []
        var positional: [String] = []
        var words = arguments.makeIterator()
        while let word = words.next() {
            guard word.hasPrefix("-") else {
                positional.append(word)
                continue
            }
            if word.hasPrefix("--expression=") {
                scripts.append(String(word.dropFirst(13)))
                continue
            }
            if word.contains(/^-[nEru]*e$/) {
                guard let script = words.next() else { return nil }
                scripts.append(script)
                continue
            }
            guard word.contains(/^-[nErus]+$/) || ["--quiet", "--silent", "--regexp-extended"].contains(word) else { return nil }
        }
        return scripts.isEmpty ? Array(positional.prefix(1)) : scripts
    }

    private static func isPlainSedScript(_ script: String) -> Bool {
        script.contains(
            /^(?:\s*(?:(?:[0-9]+|\$|\/(?:\\.|[^\/\\\n])*\/)(?:,(?:[0-9]+|\$|\/(?:\\.|[^\/\\\n])*\/))?)?\s*(?:[pdqn=]|s\/(?:\\.|[^\/\\\n])*\/(?:\\.|[^\/\\\n])*\/[gpiI0-9]*)\s*;?)+$/
        )
    }

    private static func editsInPlace(_ word: String) -> Bool {
        word.hasPrefix("--in-place") || hasShortFlag(word, in: "i")
    }
}

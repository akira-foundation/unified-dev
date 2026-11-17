import Foundation

enum OrchestratorReadList {
    private struct Form {
        enum Positionals {
            case free
            case none
            case onlyWith(Set<String>)
            case pathsInside
        }

        var flags: Set<String> = []
        var positionals = Positionals.free
        var valuesNeedEquals: Set<String> = []
        var allowsCount = false
        var allowsClusters = false

        func accepts(_ arguments: [String]) -> Bool {
            var named: [String] = []
            var positionalWords: [String] = []
            var flagsEnded = false
            for argument in arguments {
                guard argument.hasPrefix("-") else {
                    positionalWords.append(argument)
                    continue
                }
                guard !flagsEnded else { return false }
                if argument == "--" {
                    flagsEnded = true
                    continue
                }
                guard !valuesNeedEquals.contains(argument) else { return false }
                let name = String(argument.prefix { $0 != "=" })
                let isCount = allowsCount && argument.dropFirst().allSatisfy(\.isNumber) && argument.count > 1
                guard flags.contains(name) || isCount || isCluster(argument) else { return false }
                named.append(name)
            }
            switch positionals {
            case .free: return true
            case .none: return positionalWords.isEmpty
            case .onlyWith(let listing): return positionalWords.isEmpty || named.contains(where: listing.contains)
            case .pathsInside: return positionalWords.allSatisfy(Self.staysInside)
            }
        }

        private func isCluster(_ argument: String) -> Bool {
            guard allowsClusters, argument.count > 2 else { return false }
            return argument.dropFirst().allSatisfy { flags.contains("-\($0)") }
        }

        static func staysInside(_ path: String) -> Bool {
            let scalars = path.unicodeScalars
            return scalars.first != "/"
                && !scalars.split(separator: "/").contains { $0.elementsEqual("..".unicodeScalars) }
        }
    }

    private static let plainForms: [String: Form] = [
        "ls": Form(
            flags: ["-l", "-a", "-A", "-h", "-1", "-R", "-t", "-r", "-S", "-d", "-F", "-G", "-p", "-s", "-i", "-T", "-n"],
            positionals: .pathsInside,
            allowsClusters: true
        ),
        "cat": Form(flags: ["-n", "-b", "-s", "-e", "-t", "-v"], positionals: .pathsInside, allowsClusters: true),
        "grep": Form(
            flags: [
                "-n", "-i", "-l", "-L", "-w", "-x", "-c", "-E", "-F", "-r", "-R", "-v", "-o", "-h", "-H", "-e", "-A",
                "-B", "-C", "-s", "-q", "-I", "-m", "--color", "--colour", "--include", "--exclude", "--exclude-dir",
                "--line-number", "--ignore-case", "--count", "--files-with-matches", "--recursive", "--fixed-strings",
                "--extended-regexp", "--invert-match", "--word-regexp",
            ],
            positionals: .pathsInside,
            allowsClusters: true
        ),
        "head": Form(flags: ["-n", "-c"], positionals: .pathsInside, allowsCount: true),
        "tail": Form(flags: ["-n", "-c", "-r"], positionals: .pathsInside, allowsCount: true),
        "wc": Form(flags: ["-l", "-w", "-c", "-m"], positionals: .pathsInside, allowsClusters: true),
        "pwd": Form(flags: ["-L", "-P"], positionals: .none),
        "echo": Form(flags: ["-n"]),
    ]

    private static let diffFlags: Set<String> = [
        "--stat", "--shortstat", "--numstat", "--name-only", "--name-status", "--patch", "-p", "--no-patch", "-s",
        "--summary", "--color", "--no-color", "--unified", "--word-diff", "--diff-filter", "--ignore-all-space", "-w",
    ]

    private static let historyFlags: Set<String> = diffFlags.union([
        "--oneline", "--format", "--pretty", "--graph", "--decorate", "--all", "--no-merges", "--merges", "--author",
        "--since", "--until", "--after", "--before", "--grep", "--reverse", "--first-parent", "-n", "--max-count",
        "--follow", "-S", "-G", "--abbrev-commit", "--date", "--branches", "--tags", "--remotes", "--left-right",
    ])

    private static let branchListing: Set<String> = [
        "--list", "-l", "--contains", "--no-contains", "--merged", "--no-merged", "--points-at",
    ]

    private static let gitForms: [String: Form] = [
        "log": Form(flags: historyFlags, allowsCount: true),
        "show": Form(flags: historyFlags, allowsCount: true),
        "diff": Form(flags: diffFlags.union(["--cached", "--staged", "--check", "--merge-base", "--quiet", "--exit-code"])),
        "status": Form(flags: ["--short", "-s", "--branch", "-b", "-sb", "--porcelain", "--long", "--untracked-files", "-u", "--ignored"]),
        "blame": Form(flags: ["-L", "-w", "-s", "-e", "--porcelain"]),
        "grep": Form(flags: ["-n", "-i", "-l", "-w", "-e", "-c", "-E", "-F", "--name-only", "--count", "--line-number", "--ignore-case", "--cached"]),
        "ls-files": Form(flags: ["--cached", "-c", "--others", "-o", "--modified", "-m", "--exclude-standard"]),
        "merge-base": Form(flags: ["--is-ancestor", "--all", "--fork-point"]),
        "rev-parse": Form(flags: [
            "--show-toplevel", "--abbrev-ref", "--short", "--verify", "--git-dir", "--git-common-dir", "--quiet", "-q",
            "--is-inside-work-tree", "--symbolic-full-name", "--show-prefix",
        ]),
        "rev-list": Form(flags: ["--count", "--left-right", "--max-count", "--all", "--first-parent", "--no-merges", "--since", "--until"]),
        "describe": Form(flags: ["--tags", "--always", "--abbrev", "--exact-match", "--long"]),
        "shortlog": Form(flags: ["-s", "-n", "-e", "-sn", "-sne", "--all", "--no-merges", "--since", "--until"]),
        "branch": Form(
            flags: branchListing.union(["--show-current", "-a", "--all", "-r", "--remotes", "-v", "-vv", "--verbose", "--format", "--sort"]),
            positionals: .onlyWith(branchListing),
            valuesNeedEquals: ["--format", "--sort"]
        ),
        "tag": Form(
            flags: branchListing.union(["--format", "--sort", "-n"]),
            positionals: .onlyWith(branchListing),
            valuesNeedEquals: ["--format", "--sort"]
        ),
        "remote": Form(flags: ["-v", "--verbose"], positionals: .none),
        "worktree list": Form(flags: ["--porcelain"], positionals: .none),
    ]

    static let ghVerbs: [String: Set<String>] = [
        "pr": ["view", "list", "diff", "checks", "status"],
        "issue": ["view", "list", "status"],
        "run": ["view", "list"],
        "release": ["view", "list"],
        "workflow": ["view", "list"],
    ]

    private static let ghForm = Form(flags: [
        "--json", "--comments", "-c", "--state", "-s", "--limit", "-L",
        "--label", "-l", "--author", "-A", "--assignee", "-a", "--base", "-B", "--head", "-H", "--milestone", "-m",
        "--branch", "-b", "--workflow", "--log", "--log-failed", "--exit-status", "--attempt", "--job",
        "-j", "--verbose", "-v", "--status", "--event", "-e", "--name-only", "--patch", "--color", "--required",
        "--draft", "-d", "--commit", "--user", "-u", "--created", "--compact",
    ])

    static func contains(_ clause: [String]) -> Bool {
        guard let head = clause.first else { return false }
        let arguments = Array(clause.dropFirst())
        if let form = plainForms[head] { return form.accepts(arguments) }
        switch head {
        case "git": return gitReads(arguments)
        case "gh": return ghReads(arguments)
        default: return false
        }
    }

    private static func gitReads(_ arguments: [String]) -> Bool {
        let words = arguments.first == "--no-pager" ? Array(arguments.dropFirst()) : arguments
        guard let verb = words.first, words.allSatisfy({ $0.hasPrefix("-") || Form.staysInside($0) }) else { return false }
        if words.count > 1, let form = gitForms["\(verb) \(words[1])"] {
            return form.accepts(Array(words.dropFirst(2)))
        }
        return gitForms[verb]?.accepts(Array(words.dropFirst())) ?? false
    }

    private static func ghReads(_ arguments: [String]) -> Bool {
        guard arguments.count >= 2, ghVerbs[arguments[0]]?.contains(arguments[1]) == true,
              !arguments.contains(where: { $0.contains("://") }) else { return false }
        return ghForm.accepts(Array(arguments.dropFirst(2)))
    }
}

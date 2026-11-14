import Foundation

enum OrchestratorWorktreeOperands {
    private typealias Programs = OrchestratorUnaskedPrograms

    private static let searchers: Set<String> = ["grep", "egrep", "fgrep", "rg"]
    private static let searchLettersWithoutAValue = Set("nilwxcEFrvohHsqIySNuUPzL")
    private static let searchLongFlagsWithoutAValue: Set<String> = [
        "--color", "--colour", "--hidden", "--no-ignore", "--line-number", "--ignore-case", "--smart-case", "--count",
        "--files-with-matches", "--fixed-strings", "--extended-regexp", "--no-heading", "--heading", "--column",
        "--vimgrep", "--json", "--recursive", "--word-regexp", "--invert-match", "--only-matching", "--no-filename",
        "--with-filename", "--multiline", "--pcre2", "--case-sensitive", "--null", "--quiet",
    ]

    private static let ghFlagsWithoutAValue: Set<String> = ["--paginate", "--include", "-i", "--silent", "--verbose", "--slurp"]

    private static let searchLongFlagsWithAttachedValue: Set<String> = [
        "--color", "--colour", "--max-count", "--glob", "--iglob", "--type", "--type-not", "--context", "--after-context",
        "--before-context", "--max-depth", "--include", "--exclude", "--exclude-dir", "--sort", "--sortr",
    ]

    static func notPaths(_ clause: [String], head: Int) -> Set<Int> {
        let rest = (head + 1)..<clause.count
        switch Programs.name(of: clause[head]) {
        case "sed", "gsed":
            return sedScripts(clause, rest)
        case "gh":
            guard let api = rest.first(where: { clause[$0] == "api" }) else { return [] }
            let endpoint = rest.drop { $0 <= api }.first { !ghFlagsWithoutAValue.contains(clause[$0]) }
            return Set(endpoint.flatMap { clause[$0].hasPrefix("-") ? nil : [$0] } ?? [])
        case let name where searchers.contains(name):
            return searchPatterns(clause, rest)
        default:
            return []
        }
    }

    private static func sedScripts(_ clause: [String], _ rest: Range<Int>) -> Set<Int> {
        let attached = rest.filter { clause[$0].hasPrefix("--expression=") }
        let following = rest.filter { index in index > rest.lowerBound && clause[index - 1].contains(/^-[nEru]*e$/) }
        guard attached.isEmpty, following.isEmpty else { return Set(attached + following) }
        return Set(rest.first { !clause[$0].hasPrefix("-") }.map { [$0] } ?? [])
    }

    private static func searchPatterns(_ clause: [String], _ rest: Range<Int>) -> Set<Int> {
        let named = rest.filter { index in index > rest.lowerBound && ["-e", "--regexp"].contains(clause[index - 1]) }
        guard named.isEmpty else { return Set(named) }
        for index in rest {
            let word = clause[index]
            if word == "--" { return index + 1 < clause.count ? [index + 1] : [] }
            guard word.hasPrefix("-"), word != "-" else { return [index] }
            guard takesNoValue(word) else { return [] }
        }
        return []
    }

    private static func takesNoValue(_ flag: String) -> Bool {
        if flag.hasPrefix("--") {
            guard let equals = flag.firstIndex(of: "=") else { return searchLongFlagsWithoutAValue.contains(flag) }
            return searchLongFlagsWithAttachedValue.contains(String(flag[..<equals]))
        }
        if flag.contains(/^-[ABCm][0-9]+$/) { return true }
        return flag.dropFirst().allSatisfy(searchLettersWithoutAValue.contains)
    }
}

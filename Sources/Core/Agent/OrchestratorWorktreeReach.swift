import Foundation

struct OrchestratorWorktreeReach {
    typealias Verdict = OrchestratorUnaskedVerdict
    private typealias Programs = OrchestratorUnaskedPrograms

    private static let deepest = 8
    private static let mostSteps = 2_000
    private static let separators = Set(" \t\n\"'`\\()[]{}<>=@:,;|&")
    private static let scriptMarks = Set(" \t\n;|&")
    private static let globMarks = Set("*?[")
    private static let directoryChangers: Set<String> = ["cd", "pushd", "chdir"]
    private static let directoryPrefixes: Set<String> = ["builtin", "command"]
    private static let printers: Set<String> = ["echo", "printf"]
    private static let readsWhatItIsFed: Set<String> = ["xargs", "parallel", "popd"]
    private static let findFollows: Set<String> = ["-L", "-H", "-follow", "-exec", "-execdir", "-ok", "-okdir"]
    private static let followingFlags: [String: (short: String, long: [String])] = [
        "grep": ("RSO", ["--dereference-recursive"]),
        "egrep": ("RSO", ["--dereference-recursive"]),
        "fgrep": ("RSO", ["--dereference-recursive"]),
        "rg": ("L", ["--follow"]),
        "tree": ("l", []),
        "ls": ("L", ["--dereference"]),
        "du": ("L", ["--dereference"]),
        "diff": ("r", ["--recursive"]),
    ]

    private let paths: WorktreePathResolver
    private var steps = 0

    static func verdict(_ command: String, worktree: String) -> Verdict {
        var reach = OrchestratorWorktreeReach(paths: WorktreePathResolver(worktree: worktree))
        return reach.verdict(of: command, bases: [reach.paths.root], depth: 0)
    }

    private init(paths: WorktreePathResolver) {
        self.paths = paths
    }

    private mutating func verdict(of command: String, bases outer: [String], depth: Int) -> Verdict {
        steps += 1
        guard depth < Self.deepest, steps < Self.mostSteps else { return .asks }
        let parsed = OrchestratorShellParser.parseIntoSubstitutions(command)
        var bases = outer
        for clause in parsed.clauses {
            guard let change = directoryChange(in: clause) else { continue }
            guard let target = change, let reached = directories(target, from: bases) else { return .asks }
            bases += reached
        }
        for (position, clause) in parsed.clauses.enumerated() {
            if parsed.clausesWithExpansions.contains(position), !onlyPrints(clause), clause.contains(where: { $0.contains("$") }) {
                return .asks
            }
            guard self.clause(clause, bases: bases, depth: depth) == .passes else { return .asks }
        }
        return .passes
    }

    private mutating func clause(_ clause: [String], bases: [String], depth: Int) -> Verdict {
        if followsLinks(clause) { return .asks }
        let head = headIndex(clause)
        let exempt = notPaths(clause, head: head)
        for (index, word) in clause.enumerated() where index != head && !exempt.contains(index) {
            if word.contains(where: Self.scriptMarks.contains),
               verdict(of: word, bases: bases, depth: depth + 1) != .passes {
                return .asks
            }
            guard staysInside(word, bases: bases) else { return .asks }
        }
        return .passes
    }

    private func staysInside(_ word: String, bases: [String]) -> Bool {
        if word.count > 1, word.hasPrefix("=") { return false }
        if word.contains(where: Self.globMarks.contains), !word.contains(where: Self.scriptMarks.contains),
           !paths.globStaysInside(word, from: bases) {
            return false
        }
        return pieces(of: word).allSatisfy { piece in pieceStaysInside(piece, bases: bases) }
    }

    private func pieceStaysInside(_ piece: Substring, bases: [String]) -> Bool {
        if piece.hasPrefix("-") { return !piece.contains("/") && !piece.contains("~") && !piece.contains("..") }
        if piece.hasPrefix("~") {
            guard piece == "~" || piece.hasPrefix("~/") else { return false }
            return paths.staysInside(paths.home + piece.dropFirst(), from: bases)
        }
        return paths.staysInside(String(piece), from: bases)
    }

    private func pieces(of word: String) -> [Substring] {
        var rest = word[...]
        var found: [Substring] = []
        while let match = rest.firstMatch(of: /[A-Za-z][A-Za-z0-9+.\-]*:\/\/[^\s"'`]*/) {
            found += rest[..<match.range.lowerBound].split(whereSeparator: Self.separators.contains)
            if match.output.lowercased().hasPrefix("file:") { found.append("/") }
            rest = rest[match.range.upperBound...]
        }
        return found + rest.split(whereSeparator: Self.separators.contains)
    }

    private func directories(_ target: String, from bases: [String]) -> [String]? {
        guard target != "-", staysInside(target, bases: bases) else { return nil }
        var reached: [String] = []
        for base in bases {
            let start = target.hasPrefix("~") ? paths.home + target.dropFirst() : target
            guard let directory = paths.resolve(start, from: base), paths.holdsNoWayOut(below: directory) else { return nil }
            reached.append(directory)
        }
        return reached
    }

    private func directoryChange(in clause: [String]) -> String?? {
        let words = clause.drop { Programs.isKeyword($0) || OrchestratorShellJudge.isAssignment($0) }
            .drop { Self.directoryPrefixes.contains($0) }
        guard let first = words.first, Self.directoryChangers.contains(Programs.name(of: first)) else { return nil }
        return .some(words.dropFirst().first { !$0.hasPrefix("-") || $0 == "-" })
    }

    private func onlyPrints(_ clause: [String]) -> Bool {
        guard let head = headIndex(clause) else { return false }
        return Self.printers.contains(clause[head]) && !clause[head].contains("$")
    }

    private func headIndex(_ clause: [String]) -> Int? {
        clause.firstIndex { word in !Programs.isKeyword(word) && !OrchestratorShellJudge.isAssignment(word) }
    }

    private func followsLinks(_ clause: [String]) -> Bool {
        for (index, word) in clause.enumerated() {
            let name = Programs.name(of: word)
            let after = clause.dropFirst(index + 1)
            if Self.readsWhatItIsFed.contains(name) { return true }
            if name == "find", after.contains(where: Self.findFollows.contains) { return true }
            guard let flags = Self.followingFlags[name] else { continue }
            if after.contains(where: { Programs.hasShortFlag($0, in: flags.short) || Programs.names($0, oneOf: flags.long) }) {
                return true
            }
        }
        return false
    }

    private func notPaths(_ clause: [String], head: Int?) -> Set<Int> {
        guard let head else { return [] }
        let rest = clause.indices.dropFirst(head + 1)
        switch Programs.name(of: clause[head]) {
        case "sed", "gsed":
            return sedScripts(clause, rest)
        case "gh":
            guard let api = rest.first(where: { clause[$0] == "api" }) else { return [] }
            return Set(rest.drop(while: { $0 <= api }).prefix { clause[$0].hasPrefix("-") == false }.prefix(1))
        default:
            return []
        }
    }

    private func sedScripts(_ clause: [String], _ rest: Range<Int>) -> Set<Int> {
        let expressions = rest.filter { index in index > rest.startIndex && clause[index - 1].contains(/^-[nEru]*e$/) }
        if !expressions.isEmpty { return Set(expressions) }
        return Set(rest.first { !clause[$0].hasPrefix("-") }.map { [$0] } ?? [])
    }
}

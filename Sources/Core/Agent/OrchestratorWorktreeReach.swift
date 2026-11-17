import Foundation

struct OrchestratorWorktreeReach {
    typealias Verdict = OrchestratorUnaskedVerdict
    private typealias Programs = OrchestratorUnaskedPrograms

    private static let deepest = 8
    private static let mostSteps = 2_000
    private static let mostBases = 16
    private static let separators = Set(" \t\n\"'`\\()[]{}<>=@:,;|&")
    private static let scriptMarks = Set(" \t\n;|&")
    private static let globMarks = Set("*?[")
    private static let directoryChangers: Set<String> = ["cd", "pushd", "chdir"]
    private static let directoryPrefixes: Set<String> = ["builtin", "command"]
    private static let directoryFlags: Set<String> = ["-P", "-L", "--"]
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
        "shasum": ("c", ["--check"]),
        "cksum": ("c", ["--check"]),
    ]

    private let paths: WorktreePathResolver
    private var steps = 0
    private var walked: [String: Bool] = [:]

    static func verdict(_ command: String, worktree: String) -> Verdict {
        var reach = OrchestratorWorktreeReach(paths: WorktreePathResolver(worktree: worktree))
        return reach.verdict(of: command, bases: [reach.paths.root], depth: 0)
    }

    private init(paths: WorktreePathResolver) {
        self.paths = paths
    }

    private mutating func hasRoom(atDepth depth: Int) -> Bool {
        steps += 1
        return depth < Self.deepest && steps < Self.mostSteps
    }

    private mutating func verdict(of command: String, bases outer: [String], depth: Int) -> Verdict {
        guard hasRoom(atDepth: depth) else { return .asks }
        let parsed = OrchestratorShellParser.parseIntoSubstitutions(command)
        var bases = outer
        for clause in parsed.clauses {
            guard hasRoom(atDepth: depth) else { return .asks }
            guard let change = directoryChange(in: clause) else { continue }
            guard let target = change, let reached = directories(target, from: bases) else { return .asks }
            bases = Array(Set(bases + reached)).sorted()
            guard bases.count <= Self.mostBases else { return .asks }
        }
        for (position, clause) in parsed.clauses.enumerated() {
            if parsed.clausesWithExpansions.contains(position), carriesAnExpansion(clause) { return .asks }
            guard hasRoom(atDepth: depth), self.clause(clause, bases: bases, depth: depth) == .passes else { return .asks }
        }
        return .passes
    }

    private mutating func clause(_ clause: [String], bases: [String], depth: Int) -> Verdict {
        if followsLinks(clause) { return .asks }
        let head = headIndex(clause)
        let exempt = head.map { OrchestratorWorktreeOperands.notPaths(clause, head: $0) } ?? []
        let runsScripts = clause.contains { word in
            let name = Programs.name(of: word)
            return Programs.shells.contains(name) || Programs.scripted.contains(name) || Programs.runners.contains(name)
        }
        for (index, word) in clause.enumerated() where index != head && !exempt.contains(index) {
            if runsScripts, word.contains(where: Self.scriptMarks.contains),
               verdict(of: word, bases: bases, depth: depth + 1) != .passes {
                return .asks
            }
            guard staysInside(word, bases: bases) else { return .asks }
        }
        return .passes
    }

    private func carriesAnExpansion(_ clause: [String]) -> Bool {
        let printsOnly = headIndex(clause).map { Self.printers.contains(clause[$0]) } == true
        return clause.contains { word in word.contains("$") && !(printsOnly && word == "$") }
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

    private mutating func directories(_ target: String, from bases: [String]) -> [String]? {
        let named = target.hasPrefix("/") || target.hasPrefix("./") || target.hasPrefix("../") || [".", ".."].contains(target)
        guard named, staysInside(target, bases: bases) else { return nil }
        var reached: [String] = []
        for base in bases {
            guard let directory = paths.resolve(target, from: base), paths.isDirectory(directory) else { return nil }
            if walked[directory] == nil { walked[directory] = paths.holdsNoWayOut(below: directory) }
            guard walked[directory] == true else { return nil }
            reached.append(directory)
        }
        return reached
    }

    private func directoryChange(in clause: [String]) -> String?? {
        let words = clause.drop { Programs.isKeyword($0) || OrchestratorShellJudge.isAssignment($0) }
            .drop { Self.directoryPrefixes.contains($0) }
        guard let first = words.first, Self.directoryChangers.contains(Programs.name(of: first)) else { return nil }
        let operands = words.dropFirst().filter { !Self.directoryFlags.contains($0) }
        guard operands.count == 1, let target = operands.first, !target.hasPrefix("-"), !target.hasPrefix("+") else {
            return .some(nil)
        }
        return .some(target)
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
}

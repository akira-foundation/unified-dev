import Foundation

enum OrchestratorUnaskedVerdict: Int, Comparable {
    case passes
    case asks
    case refused

    static func < (left: Self, right: Self) -> Bool { left.rawValue < right.rawValue }
}

struct OrchestratorUnaskedJudge {
    typealias Verdict = OrchestratorUnaskedVerdict
    private typealias Programs = OrchestratorUnaskedPrograms

    private static let deepest = 8
    private static let mostSteps = 20_000

    private var steps = 0

    static func verdict(_ command: String) -> Verdict {
        var judge = OrchestratorUnaskedJudge()
        return judge.verdict(of: command, depth: 0)
    }

    static func isSimple(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy(Programs.simpleWord.contains)
    }

    private mutating func hasRoom(atDepth depth: Int) -> Bool {
        steps += 1
        return depth < Self.deepest && steps < Self.mostSteps
    }

    private mutating func verdict(of command: String, depth: Int) -> Verdict {
        guard hasRoom(atDepth: depth) else { return .asks }
        let parsed = OrchestratorShellParser.parseIntoSubstitutions(command)
        if parsed.writesFile { return .refused }
        guard !parsed.clauses.isEmpty else { return .asks }
        var worst: Verdict = parsed.isUnreadable ? .asks : .passes
        for (position, clause) in parsed.clauses.enumerated() {
            worst = max(worst, self.clause(clause, depth: depth))
            if parsed.clausesWithExpansions.contains(position), clause.contains(where: Programs.decidesByItsWords) {
                worst = max(worst, .asks)
            }
        }
        return worst
    }

    private mutating func clause(_ clause: [String], depth: Int) -> Verdict {
        guard hasRoom(atDepth: depth) else { return .asks }
        let unkeyed = Array(clause.drop(while: Programs.isKeyword))
        let words = Array(unkeyed.drop(while: OrchestratorShellJudge.isAssignment))
        let assigned = unkeyed.prefix(unkeyed.count - words.count)
        guard let first = words.first else {
            return assigned.allSatisfy(Programs.staysInThisShell) ? .passes : .asks
        }
        let judged = command(first, Array(words.dropFirst()), depth: depth)
        return assigned.isEmpty ? judged : max(judged, .asks)
    }

    private mutating func command(_ first: String, _ rest: [String], depth: Int) -> Verdict {
        if Programs.tests.contains(first) { return Programs.isPlainTest(rest) ? .passes : .asks }
        guard Self.isSimple(first) else { return .asks }
        let head = Programs.name(of: first)
        switch head {
        case "git":
            return OrchestratorUnaskedGit.verdict(rest)
        case "gh":
            return OrchestratorUnaskedGit.ghVerdict(rest)
        case "find":
            return find(rest, depth: depth)
        case _ where head.hasPrefix("git-"):
            return OrchestratorShellJudge.gitVerbs.contains(String(head.dropFirst(4))) ? .refused : .asks
        case _ where Programs.shells.contains(head):
            return shell(rest, depth: depth)
        case _ where Programs.scripted.contains(head):
            return verdict(of: (rest.first == "--" ? rest.dropFirst() : rest[...]).joined(separator: " "), depth: depth + 1)
        case _ where Programs.leftWithTheOwner.contains(head):
            return .asks
        case _ where Programs.runners.contains(head):
            return max(runner(rest, depth: depth), Programs.ownVerdict(ofRunner: head, rest))
        default:
            return Programs.verdict(of: head, rest)
        }
    }

    private mutating func shell(_ arguments: [String], depth: Int) -> Verdict {
        let words = arguments.compactMap { argument -> String? in
            if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
                return String(argument[argument.index(after: equals)...])
            }
            return argument.hasPrefix("-") ? nil : argument
        }
        guard !words.isEmpty else { return .asks }
        var worst: Verdict = arguments.contains(where: Programs.keepsAScriptOutOfSight) ? .asks : .passes
        for word in words {
            worst = max(worst, verdict(of: word, depth: depth + 1))
        }
        return worst
    }

    private mutating func find(_ arguments: [String], depth: Int) -> Verdict {
        if arguments.contains(where: { word in Programs.findWriters.contains { word.hasPrefix($0) } }) {
            return .refused
        }
        var worst = Verdict.passes
        for index in arguments.indices where Programs.findRunners.contains(arguments[index]) {
            let start = index + 1
            guard start < arguments.count else { return .asks }
            worst = max(worst, clause(Array(arguments[start...]), depth: depth + 1))
        }
        return worst
    }

    private mutating func runner(_ arguments: [String], depth: Int) -> Verdict {
        var worst = Verdict.passes
        var run: Verdict?
        for index in arguments.indices {
            let word = arguments[index]
            guard Self.isSimple(word) || OrchestratorShellJudge.isAssignment(word) else {
                worst = max(worst, wordWithSpacesOrUnread(word, depth: depth))
                continue
            }
            if Programs.runners.contains(Programs.name(of: word)) { continue }
            let judged = clause(Array(arguments[index...]), depth: depth + 1)
            if judged == .refused { worst = .refused }
            if run == nil, !Programs.isAnOption(word) { run = judged }
        }
        return max(worst, run ?? .passes)
    }

    private mutating func wordWithSpacesOrUnread(_ word: String, depth: Int) -> Verdict {
        guard word.contains(" "), !word.hasPrefix("-"), !word.contains("$"), !word.contains("`") else { return .asks }
        return verdict(of: word, depth: depth + 1)
    }
}

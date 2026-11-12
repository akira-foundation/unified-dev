import Foundation

enum OrchestratorUnaskedGit {
    typealias Verdict = OrchestratorUnaskedVerdict

    private static let flagsTakingAWord: Set<String> = [
        "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env", "--attr-source",
    ]
    private static let flagsThatRedirectGit = ["-c", "--config-env", "--exec-path", "--git-dir", "--work-tree", "--namespace"]
    private static let reads: Set<String> = [
        "status", "log", "diff", "show", "blame", "shortlog", "describe", "rev-parse", "rev-list", "ls-files", "ls-tree",
        "ls-remote", "merge-base", "cat-file", "grep", "for-each-ref", "show-ref", "name-rev", "whatchanged", "fetch",
        "count-objects", "diff-tree", "cherry", "check-ignore", "var", "version",
    ]
    private static let flagsThatWriteOrRun = [
        "--output", "-O", "--open-files-in-pager", "--upload-pack", "--receive-pack", "--exec", "--ext-diff", "--no-index",
    ]
    private static let fetchFlagsThatMoveBranches = ["--prune", "--update-head-ok", "--force", "--set-upstream"]
    private static let fetchShortFlagsThatMoveBranches = "pPuf"
    private static let lsRemoteShortFlagsThatRun = "u"

    private static let ghReadVerbs = OrchestratorReadList.ghVerbs.merging(["repo": ["view", "list"], "label": ["list"]]) {
        $0.union($1)
    }
    private static let ghFlagsThatWait = ["--watch", "--interval"]
    private static let ghCommandsThatOnlyRead: Set<String> = ["search", "api", "status"]
    private static let ghWritingFlags = ["--method", "--field", "--raw-field", "--input"]
    private static let ghWritingShortFlags = "XFf"
    private static let ghVerbsWhereShortWIsNotTheBrowser: Set<String> = ["run list"]

    static func verdict(_ arguments: [String]) -> Verdict {
        var index = 0
        while index < arguments.count, arguments[index].hasPrefix("-") {
            index += flagsTakingAWord.contains(arguments[index]) ? 2 : 1
        }
        guard index < arguments.count, OrchestratorUnaskedJudge.isSimple(arguments[index]) else { return .asks }
        let verb = arguments[index]
        if OrchestratorShellJudge.gitVerbs.contains(verb) { return .refused }
        let global = arguments[..<index]
        if global.contains(where: { flag in flagsThatRedirectGit.contains { flag == $0 || flag.hasPrefix("\($0)=") } }) {
            return .asks
        }
        guard reads.contains(verb) else {
            return OrchestratorReadList.contains(["git"] + arguments) ? .passes : .asks
        }
        let after = Array(arguments[(index + 1)...])
        if verb == "fetch", after.contains(where: movesBranches) { return .asks }
        if verb == "ls-remote", after.contains(where: { OrchestratorUnaskedPrograms.hasShortFlag($0, in: lsRemoteShortFlagsThatRun) }) {
            return .asks
        }
        return after.contains { word in
            OrchestratorUnaskedPrograms.names(word, oneOf: flagsThatWriteOrRun) || OrchestratorUnaskedPrograms.hasShortFlag(word, in: "O")
        } ? .asks : .passes
    }

    private static func movesBranches(_ word: String) -> Bool {
        word.contains(":") || word.hasPrefix("+") || word == "tag" || OrchestratorUnaskedPrograms.names(word, oneOf: fetchFlagsThatMoveBranches)
            || OrchestratorUnaskedPrograms.hasShortFlag(word, in: fetchShortFlagsThatMoveBranches)
    }

    static func ghVerdict(_ arguments: [String]) -> Verdict {
        let positional = arguments.filter { !$0.hasPrefix("-") }
        guard let command = positional.first else { return .passes }
        let changesTheBranch = positional.contains("merge") || positional.contains("checkout")
        if arguments.prefix(2).contains(where: { $0.hasPrefix("-") }) {
            return positional.contains("pr") && changesTheBranch ? .refused : .asks
        }
        guard positional.prefix(2).allSatisfy(OrchestratorUnaskedJudge.isSimple) else { return .asks }
        let verb = positional.count > 1 ? positional[1] : ""
        if command == "pr", ["merge", "checkout"].contains(verb) { return .refused }
        guard ghCommandsThatOnlyRead.contains(command) || ghReadVerbs[command]?.contains(verb) == true else { return .asks }
        let shortWIsTheBrowser = !ghVerbsWhereShortWIsNotTheBrowser.contains("\(command) \(verb)")
        if arguments.contains(where: { opensABrowser($0, shortWIsTheBrowser: shortWIsTheBrowser) }) { return .asks }
        if reachesAnotherHost(arguments, command: command, verb: verb) { return .asks }
        if arguments.contains(where: { OrchestratorUnaskedPrograms.names($0, oneOf: ghFlagsThatWait) }) { return .asks }
        let writes = command == "api" && arguments.contains { word in
            word.contains("$") || OrchestratorUnaskedPrograms.names(word, oneOf: ghWritingFlags)
                || OrchestratorUnaskedPrograms.hasShortFlag(word, in: ghWritingShortFlags)
        }
        return writes ? .asks : .passes
    }

    private static func opensABrowser(_ word: String, shortWIsTheBrowser: Bool) -> Bool {
        OrchestratorUnaskedPrograms.names(word, oneOf: ["--web"])
            || (shortWIsTheBrowser && OrchestratorUnaskedPrograms.hasShortFlag(word, in: "w"))
    }

    private static func reachesAnotherHost(_ arguments: [String], command: String, verb: String) -> Bool {
        if arguments.contains(where: { OrchestratorUnaskedPrograms.names($0, oneOf: ["--hostname"]) }) { return true }
        if arguments.contains(where: { $0.contains("://") && !isOnGitHub($0[...]) }) { return true }
        return repositories(arguments, command: command, verb: verb).contains(where: namesAnotherHost)
    }

    private static func repositories(_ arguments: [String], command: String, verb: String) -> [Substring] {
        var named: [Substring] = []
        for (index, word) in arguments.enumerated() {
            let next = index + 1 < arguments.count ? arguments[index + 1][...] : ""
            if word == "--repo" { named.append(next) }
            if word.hasPrefix("--repo=") { named.append(word.dropFirst(7)) }
            if !word.hasPrefix("--"), word.hasPrefix("-"), let flag = word.firstIndex(of: "R") {
                let attached = word[word.index(after: flag)...]
                named.append(attached.isEmpty ? next : attached)
            }
        }
        if command == "repo", verb == "view", let viewed = arguments.dropFirst(2).first(where: { !$0.hasPrefix("-") }) {
            named.append(viewed[...])
        }
        return named
    }

    private static func namesAnotherHost(_ repository: Substring) -> Bool {
        if repository.contains("://") { return !isOnGitHub(repository) }
        if repository.contains("@") { return !["git@github.com:", "git@github.com/"].contains { repository.hasPrefix($0) } }
        let segments = repository.split(separator: "/", omittingEmptySubsequences: false)
        return segments.count > 2 && segments[0].lowercased() != "github.com"
    }

    private static func isOnGitHub(_ address: Substring) -> Bool {
        ["https://github.com/", "https://api.github.com/"].contains { address.hasPrefix($0) }
    }
}

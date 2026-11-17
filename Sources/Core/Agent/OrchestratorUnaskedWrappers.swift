import Foundation

enum OrchestratorUnaskedWrappers {
    private struct Options {
        var plain: Set<String> = []
        var takingAValue: Set<String> = []
        var leadingDuration = false
        var attachedNumber = false
    }

    private static let options: [String: Options] = [
        "env": Options(plain: ["-i", "-0", "-v", "-", "--ignore-environment", "--null"], takingAValue: ["-u", "--unset"]),
        "command": Options(plain: ["-p", "-v", "-V"]),
        "builtin": Options(),
        "time": Options(plain: ["-p", "-l", "-h", "--portability"]),
        "nice": Options(takingAValue: ["-n", "--adjustment"], attachedNumber: true),
        "timeout": timeout,
        "gtimeout": timeout,
        "nohup": Options(),
        "stdbuf": Options(takingAValue: ["-i", "-o", "-e", "--input", "--output", "--error"]),
        "xargs": Options(
            plain: ["-0", "-t", "-r", "-x", "--null", "--no-run-if-empty", "--verbose", "--exit"],
            takingAValue: [
                "-n", "-L", "-P", "-s", "-E", "-d", "--max-args", "--max-lines", "--max-procs", "--max-chars", "--eof",
                "--delimiter",
            ]
        ),
        "noglob": Options(),
        "nocorrect": Options(),
    ]

    private static let timeout = Options(
        plain: ["--preserve-status", "--foreground", "-v", "--verbose", "-f", "-p"],
        takingAValue: ["-s", "--signal", "-k", "--kill-after"],
        leadingDuration: true
    )

    static var names: Set<String> { Set(options.keys) }

    static func command(of wrapper: String, _ arguments: [String]) -> [String]? {
        guard let known = options[wrapper] else { return nil }
        var index = arguments.startIndex
        while index < arguments.endIndex, arguments[index].hasPrefix("-") {
            let word = arguments[index]
            index += 1
            if word == "--" { break }
            if known.plain.contains(word) { continue }
            if known.takingAValue.contains(word) {
                guard index < arguments.endIndex else { return nil }
                index += 1
                continue
            }
            guard carriesItsValue(word, known) else { return nil }
        }
        let rest = Array(arguments[index...])
        guard known.leadingDuration else { return rest }
        guard let duration = rest.first, duration.contains(/^[0-9][0-9.]*[smhd]?$/) else { return nil }
        return Array(rest.dropFirst())
    }

    private static func carriesItsValue(_ word: String, _ known: Options) -> Bool {
        if known.attachedNumber, word.contains(/^-n?[0-9]+$/) { return true }
        if word.hasPrefix("--") {
            return known.takingAValue.contains(String(word.prefix { $0 != "=" })) && word.contains("=")
        }
        return word.count > 2 && known.takingAValue.contains(String(word.prefix(2)))
    }
}

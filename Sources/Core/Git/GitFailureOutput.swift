import Foundation

public enum GitFailureOutput {
    static let noisePrefixes = [
        "Cloning into", "hint:", "** ", "Usage:", "Warning: Permanently added",
        "Please make sure you have the correct access rights", "and the repository exists.",
        "Receiving objects:", "Resolving deltas:", "Updating files:", "Checking out files:",
        "remote: Enumerating objects:", "remote: Counting objects:", "remote: Compressing objects:",
        "remote: Total ",
    ]

    static let generic = [
        "fatal: Could not read from remote repository.",
        "fatal: the remote end hung up unexpectedly",
    ]

    public static func lines(of output: String) -> [String] {
        output
            .components(separatedBy: CharacterSet(charactersIn: "\n\r"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func cause(in output: String) -> String? {
        let meaningful = lines(of: output).filter { !isNoise($0) }
        let specific = meaningful.first { line in !generic.contains { line.hasPrefix($0) } }
        return specific ?? meaningful.first
    }

    static func isNoise(_ line: String) -> Bool {
        line == "remote:" || noisePrefixes.contains { line.hasPrefix($0) }
    }
}

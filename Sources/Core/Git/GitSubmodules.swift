import Foundation

extension Git {
    public static func hasSubmodules(in worktree: String) -> Bool {
        FileManager.default.fileExists(atPath: (worktree as NSString).appendingPathComponent(".gitmodules"))
    }

    public static func initialiseSubmodules(in worktree: String, timeout: Duration = .seconds(120)) async throws -> String {
        guard hasSubmodules(in: worktree) else { return "" }
        try Task.checkCancellation()
        let arguments = ["submodule", "update", "--init", "--recursive"]
        let result = try await runAgainstRemote(arguments, in: worktree, timeout: timeout)
        guard result.ok else { throw error(arguments, result.status, result.stderr, result.stdout) }
        return result.stdout + result.stderr
    }
}

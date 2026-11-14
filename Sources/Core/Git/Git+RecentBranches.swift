import Foundation

extension Git {
    public static func recentBranches(of repo: String, count: Int = 20) async -> [RecentBranch] {
        let arguments = [
            "for-each-ref", "--sort=-committerdate", "--count=\(count)",
            "--format=%(refname:short)%09%(committerdate:unix)", "refs/heads",
        ]
        guard let result = try? await run(arguments, in: repo), result.ok else { return [] }
        return RecentBranch.parse(result.stdout)
    }
}

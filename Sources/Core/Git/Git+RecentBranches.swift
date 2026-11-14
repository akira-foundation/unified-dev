import Foundation

public struct RecentBranch: Sendable, Hashable {
    public let name: String
    public let touched: Date

    public init(name: String, touched: Date) {
        self.name = name
        self.touched = touched
    }

    static func parse(_ output: String) -> [RecentBranch] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, !fields[0].isEmpty,
                  let seconds = TimeInterval(fields[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            return RecentBranch(name: String(fields[0]), touched: Date(timeIntervalSince1970: seconds))
        }
    }
}

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

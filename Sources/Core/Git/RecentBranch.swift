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

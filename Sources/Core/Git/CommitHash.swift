import Foundation

public enum CommitHash {
    public static let shortestAbbreviation = 12

    public static func same(_ first: String?, _ second: String?) -> Bool {
        guard let first, let second, !first.isEmpty, !second.isEmpty else { return false }
        if first == second { return true }
        let lower = (first.lowercased(), second.lowercased())
        guard lower.0.allSatisfy(\.isHexDigit), lower.1.allSatisfy(\.isHexDigit) else { return false }
        let (short, long) = lower.0.count < lower.1.count ? lower : (lower.1, lower.0)
        return short.count >= shortestAbbreviation && long.hasPrefix(short)
    }
}

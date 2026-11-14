import Foundation

public enum ProseList {
    public static func joined(_ words: [String]) -> String {
        guard words.count > 1, let last = words.last else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " and " + last
    }
}

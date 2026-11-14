import Foundation

public struct AssignedIssue: Sendable, Hashable, Identifiable {
    public let number: Int
    public let title: String

    public var id: Int { number }

    public init(number: Int, title: String) {
        self.number = number
        self.title = title
    }
}

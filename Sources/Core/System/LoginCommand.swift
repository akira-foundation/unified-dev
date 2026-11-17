import Foundation

public struct LoginCommand: Sendable, Equatable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
    }

    public init?(parsing command: String?) {
        let words = (command ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        guard let executable = words.first else { return nil }
        self.init(executable: executable, arguments: Array(words.dropFirst()))
    }

    public var label: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

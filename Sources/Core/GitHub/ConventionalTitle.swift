import Foundation

public struct ConventionalTitle: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case feat, fix, perf, refactor, docs, style, test, ci, chore
    }

    public static let shape = "<type>(<scope>): <description>"

    public static var typeChoices: String {
        let types = Kind.allCases.map(\.rawValue)
        return types.dropLast().joined(separator: ", ") + " or " + (types.last ?? "")
    }

    public let kind: Kind
    public let scope: String?
    public let isBreaking: Bool
    public let summary: String

    public init?(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.contains(where: \.isNewline),
              let colon = trimmed.firstIndex(of: ":")
        else { return nil }

        let rest = trimmed[trimmed.index(after: colon)...]
        guard rest.first == " " else { return nil }
        let summary = rest.dropFirst()
        guard let first = summary.first, !first.isWhitespace else { return nil }

        var head = trimmed[..<colon]
        let isBreaking = head.last == "!"
        if isBreaking { head = head.dropLast() }

        var scope: String?
        if head.last == ")" {
            guard let open = head.firstIndex(of: "(") else { return nil }
            let inner = head[head.index(after: open)..<head.index(before: head.endIndex)]
            guard Self.isScope(inner) else { return nil }
            scope = String(inner)
            head = head[..<open]
        }

        guard let kind = Kind(rawValue: String(head)) else { return nil }
        self.kind = kind
        self.scope = scope
        self.isBreaking = isBreaking
        self.summary = String(summary)
    }

    public static func isConventional(_ title: String) -> Bool {
        ConventionalTitle(title) != nil
    }

    public static func endsWithNumber(_ title: String, _ number: Int) -> Bool {
        title.trimmingCharacters(in: .whitespaces).hasSuffix("(#\(number))")
    }

    private static func isScope(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || "-_./".contains(character))
        }
    }
}

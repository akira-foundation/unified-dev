import Foundation

enum HTMLMetaCharset {
    private static let comment = try? NSRegularExpression(pattern: "<!--(?:-?>|[\\s\\S]*?(?:-->|$))")
    private static let space = "[\\t\\n\\f\\r ]"
    private static let tag = try? NSRegularExpression(
        pattern: "<meta[\\t\\n\\f\\r /](?:[^>\"']|\"[^\"]*\"|'[^']*')*>", options: [.caseInsensitive]
    )
    private static let attribute = try? NSRegularExpression(
        pattern: "([^\\t\\n\\f\\r =/>]+)(?:\(space)*=\(space)*(\"[^\"]*\"|'[^']*'|[^\\t\\n\\f\\r >]*))?"
    )
    private static let contentCharset = try? NSRegularExpression(
        pattern: "charset\(space)*=\(space)*[\"']?([^\"'\\t\\n\\f\\r ;]+)", options: [.caseInsensitive]
    )

    static func declared(in prescan: String, accepting accept: (String) -> String?) -> String? {
        guard let comment, let tag else { return nil }
        let text = comment.stringByReplacingMatches(in: prescan, range: whole(prescan), withTemplate: "")
        for match in tag.matches(in: text, range: whole(text)) {
            guard let range = Range(match.range, in: text) else { continue }
            if let label = label(inTag: String(text[range])).flatMap(accept) { return label }
        }
        return nil
    }

    private static func label(inTag tagText: String) -> String? {
        let attributes = attributes(of: tagText)
        if let charset = attributes["charset"] { return charset }
        guard attributes["http-equiv"]?.lowercased() == "content-type", let content = attributes["content"],
              let contentCharset,
              let match = contentCharset.firstMatch(in: content, range: whole(content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        return String(content[range])
    }

    private static func attributes(of tagText: String) -> [String: String] {
        guard let attribute else { return [:] }
        let body = String(tagText.dropFirst("<meta".count).dropLast())
        var found: [String: String] = [:]
        for match in attribute.matches(in: body, range: whole(body)) {
            guard let nameRange = Range(match.range(at: 1), in: body) else { continue }
            let name = body[nameRange].lowercased()
            guard found[name] == nil else { continue }
            let value = Range(match.range(at: 2), in: body).map { unquoted(String(body[$0])) } ?? ""
            found[name] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\t\n\u{0C}\r "))
        }
        return found
    }

    private static func unquoted(_ value: String) -> String {
        guard let first = value.first, first == "\"" || first == "'", value.count >= 2, value.last == first else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    private static func whole(_ text: String) -> NSRange {
        NSRange(text.startIndex..., in: text)
    }
}

import Foundation

enum TOMLScan {
    struct Outline {
        var headers: [(index: Int, path: [String], isArray: Bool)] = []
        var assignments: [(index: Int, end: Int)] = []
    }

    static func outline(_ lines: [String]) -> Outline {
        var outline = Outline()
        var index = 0
        while index < lines.count {
            if let path = SettingsDocument.tableHeader(in: lines[index]) {
                let isArray = lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[[")
                outline.headers.append((index, path, isArray))
                index += 1
                continue
            }
            guard SettingsDocument.keyAssignment(in: lines[index]) != nil else {
                index += 1
                continue
            }
            let end = end(of: lines, from: index)
            outline.assignments.append((index, end))
            index = end
        }
        return outline
    }

    static func withoutTrailingComment(_ text: String) -> String {
        let scanned = scan(text)
        guard let hash = scanned.comment else { return text }
        return text[..<hash].trimmingCharacters(in: .whitespaces)
    }
    static func value(of line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        return line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
    }

    static func end(of lines: [String], from index: Int) -> Int {
        guard let value = value(of: lines[index]) else { return index + 1 }

        for delimiter in ["'''", "\"\"\""] where value.hasPrefix(delimiter) {
            if value.dropFirst(delimiter.count).contains(delimiter) { return index + 1 }
            var cursor = index + 1
            while cursor < lines.count {
                if lines[cursor].contains(delimiter) { return cursor + 1 }
                cursor += 1
            }
            return lines.count
        }

        guard value.hasPrefix("[") || value.hasPrefix("{") else { return index + 1 }
        var text = value
        var cursor = index
        while scan(text).depth > 0 {
            cursor += 1
            guard cursor < lines.count else { return lines.count }
            text += "\n" + lines[cursor]
        }
        return cursor + 1
    }

    static func inlineTable(_ value: String) -> (entries: [String], comment: String?)? {
        guard value.hasPrefix("{") else { return nil }
        let outer = scan(value)
        guard outer.depth == 0, let close = outer.close else { return nil }
        let after = value[value.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard after.isEmpty || after.hasPrefix("#") else { return nil }
        let inner = String(value[value.index(after: value.startIndex)..<close])
        let entries = scan(inner, splittingAt: ",").parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (entries, after.isEmpty ? nil : after)
    }

    private static func scan(
        _ text: String, splittingAt separator: Character? = nil
    ) -> (parts: [String], depth: Int, close: String.Index?, comment: String.Index?) {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var close: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character != "\"", character != "'" else {
                let end = stringEnd(in: text, from: index)
                current += text[index..<end]
                index = end
                continue
            }
            if character == "#" {
                guard let newline = text[index...].firstIndex(of: "\n") else {
                    return (parts + [current], depth, close, index)
                }
                index = newline
                continue
            }
            switch character {
            case "{", "[": depth += 1
            case "}", "]":
                depth -= 1
                if depth == 0, close == nil, character == "}" { close = index }
            default: break
            }
            index = text.index(after: index)
            guard character == separator, depth == 0 else {
                current.append(character)
                continue
            }
            parts.append(current)
            current = ""
        }
        return (parts + [current], depth, close, nil)
    }

    private static func stringEnd(in text: String, from start: String.Index) -> String.Index {
        let quote = text[start]
        let triple = String(repeating: quote, count: 3)
        let delimiter = text[start...].hasPrefix(triple) ? triple : String(quote)
        var cursor = text.index(start, offsetBy: delimiter.count)
        while cursor < text.endIndex {
            guard quote != "\"" || text[cursor] != "\\" else {
                cursor = text.index(cursor, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            if text[cursor...].hasPrefix(delimiter) { return text.index(cursor, offsetBy: delimiter.count) }
            cursor = text.index(after: cursor)
        }
        return text.endIndex
    }
}

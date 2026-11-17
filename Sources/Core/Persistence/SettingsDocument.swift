import Foundation

public enum TOMLLiteral: Sendable, Hashable {
    case string(String)
    case boolean(Bool)
    case strings([String])
}

public struct SettingsDocument: Sendable, Equatable {
    private var lines: [String]
    private var hadTrailingNewline: Bool
    public private(set) var exists: Bool

    public init(text: String, exists: Bool = true) {
        hadTrailingNewline = text.isEmpty || text.hasSuffix("\n")
        var body = text
        if hadTrailingNewline, !body.isEmpty { body.removeLast() }
        lines = body.isEmpty ? [] : body.components(separatedBy: "\n")
        self.exists = exists
    }

    public init(contentsOf path: String) {
        if let text = try? String(contentsOfFile: path, encoding: .utf8) {
            self.init(text: text, exists: true)
        } else {
            self.init(text: "", exists: false)
        }
    }

    public var text: String {
        let body = lines.joined(separator: "\n")
        if body.isEmpty { return "" }
        return hadTrailingNewline ? body + "\n" : body
    }

    public var isEmpty: Bool {
        lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public mutating func set(_ value: TOMLLiteral, at path: [String]) {
        guard !path.isEmpty else { return }
        let rendered = Self.render(value)

        if locate(path) == nil { openInlineTables(along: path) }
        if let found = locate(path) {
            let replacement = "\(found.indent)\(found.writtenKey) = \(rendered)"
            lines.replaceSubrange(found.range, with: replacement.components(separatedBy: "\n"))
            return
        }
        if let dotted = addingDottedKey(rendered, at: path) {
            self = dotted
            return
        }

        insert(key: path.last!, rendered: rendered, inTable: Array(path.dropLast()))
    }

    public mutating func remove(at path: [String]) {
        var opened = self
        if opened.locate(path) == nil { opened.openInlineTables(along: path) }
        guard let found = opened.locate(path) else { return }
        opened.lines.removeSubrange(found.range)
        self = opened
    }

    public mutating func removeTable(at path: [String]) {
        guard let range = tableRange(path), let header = headerIndex(path) else { return }
        lines.removeSubrange(header..<range.upperBound)
    }

    public func tables(under path: [String]) -> [[String]] {
        TOMLScan.outline(lines).headers.compactMap { found in
            let header = found.path
            guard header.count == path.count + 1, Array(header.dropLast()) == path else { return nil }
            return header
        }
    }

    public func write(to path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func render(_ value: TOMLLiteral) -> String {
        switch value {
        case .boolean(let flag):
            return flag ? "true" : "false"
        case .strings(let items):
            return "[" + items.map { quoted($0) }.joined(separator: ", ") + "]"
        case .string(let text):
            guard text.contains("\n") else { return quoted(text) }
            if !text.contains("'''") {
                return "'''\n\(text)\n'''"
            }
            return "\"\"\"\n\(escaped(text))\n\"\"\""
        }
    }

    private static func quoted(_ text: String) -> String {
        if text.contains("\\"), !text.contains("'"), !text.contains("\n") {
            return "'\(text)'"
        }
        return "\"\(escaped(text))\""
    }

    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text.unicodeScalars {
            switch character {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            default: result.unicodeScalars.append(character)
            }
        }
        return result
    }

    private struct Located {
        var range: Range<Int>
        var indent: String
        var writtenKey: String
    }

    private func locate(_ path: [String]) -> Located? {
        for split in stride(from: path.count - 1, through: 0, by: -1) {
            let table = Array(path.prefix(split))
            let key = Array(path.dropFirst(split))
            guard let range = tableRange(table) else { continue }
            if let found = findKey(key, in: range) { return found }
        }
        return nil
    }

    private func headerIndex(_ table: [String]) -> Int? {
        guard !table.isEmpty else { return nil }
        return TOMLScan.outline(lines).headers.first { $0.path == table }?.index
    }

    private func tableRange(_ table: [String]) -> Range<Int>? {
        var start: Int
        if table.isEmpty {
            start = 0
        } else {
            guard let header = headerIndex(table) else { return nil }
            start = header + 1
        }
        let end = TOMLScan.outline(lines).headers.first { $0.index >= start }?.index ?? lines.count
        return start..<end
    }

    private func findKey(_ key: [String], in range: Range<Int>) -> Located? {
        for found in TOMLScan.outline(lines).assignments where range.contains(found.index) {
            guard let (written, indent) = Self.keyAssignment(in: lines[found.index]), written == key else {
                continue
            }
            let index = found.index
            let end = found.end
            return Located(
                range: index..<end,
                indent: indent,
                writtenKey: Self.written(key)
            )
        }
        return nil
    }

    private mutating func insert(key: String, rendered: String, inTable table: [String]) {
        let line = "\(Self.written([key])) = \(rendered)"

        if let range = tableRange(table) {
            var insertion = range.upperBound
            while insertion > range.lowerBound,
                  lines[insertion - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertion -= 1
            }
            lines.insert(contentsOf: line.components(separatedBy: "\n"), at: insertion)
            return
        }

        if !lines.isEmpty, !(lines.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) {
            lines.append("")
        }
        let header = "[" + Self.written(table) + "]"
        lines.append(header)
        lines.append(contentsOf: line.components(separatedBy: "\n"))
    }

    static func written(_ key: some Sequence<String>) -> String {
        key.map { needsQuoting($0) ? "\"\($0)\"" : $0 }.joined(separator: ".")
    }

    private static func needsQuoting(_ key: String) -> Bool {
        key.isEmpty || key.contains { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    static func tableHeader(in line: String) -> [String]? {
        let trimmed = TOMLScan.withoutTrailingComment(line.trimmingCharacters(in: .whitespaces))
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        var inner = trimmed.dropFirst().dropLast()
        if inner.hasPrefix("["), inner.hasSuffix("]") {
            inner = inner.dropFirst().dropLast()
        }
        let path = splitKey(String(inner))
        return path.isEmpty ? nil : path
    }

    static func keyAssignment(in line: String) -> ([String], String)? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let head = String(line[line.startIndex..<equals])
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("[") else { return nil }
        let indent = String(head.prefix { $0 == " " || $0 == "\t" })
        let path = splitKey(trimmed)
        return path.isEmpty ? nil : (path, indent)
    }

    static func splitKey(_ text: String) -> [String] {
        var components: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let active = quote {
                if character == active { quote = nil } else { current.append(character) }
                continue
            }
            switch character {
            case "\"", "'": quote = character
            case ".":
                components.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default: current.append(character)
            }
        }
        components.append(current.trimmingCharacters(in: .whitespaces))
        return components.filter { !$0.isEmpty }
    }
}

import Foundation

extension SettingsDocument {
    mutating func openInlineTables(along path: [String]) {
        let table = Array(path.dropLast())
        for _ in table.indices {
            guard let opened = openingOneInlineTable(under: table) else { return }
            self = opened
        }
    }

    func addingDottedKey(_ rendered: String, at path: [String]) -> SettingsDocument? {
        let table = Array(path.dropLast())
        var lines = text.components(separatedBy: "\n")
        guard !TOMLScan.outline(lines).headers.contains(where: { $0.path == table }) else { return nil }
        var insertion: (index: Int, indent: String, owner: [String])?
        for assignment in Self.assignments(in: lines) {
            let full = assignment.table + assignment.key
            guard assignment.table.count < table.count,
                  full.count > table.count,
                  Array(full.prefix(table.count)) == table
            else { continue }
            insertion = (assignment.end, assignment.indent, assignment.table)
        }
        guard let insertion else { return nil }
        let line = "\(insertion.indent)\(Self.written(path.dropFirst(insertion.owner.count))) = \(rendered)"
        lines.insert(contentsOf: line.components(separatedBy: "\n"), at: insertion.index)
        return SettingsDocument(text: lines.joined(separator: "\n"), exists: exists)
    }

    private func openingOneInlineTable(under table: [String]) -> SettingsDocument? {
        var lines = text.components(separatedBy: "\n")
        let headers = Set(TOMLScan.outline(lines).headers.map(\.path))
        for assignment in Self.assignments(in: lines) {
            let full = assignment.table + assignment.key
            guard assignment.end == assignment.index + 1,
                  full.count <= table.count,
                  Array(table.prefix(full.count)) == full,
                  !headers.contains(full),
                  let value = TOMLScan.value(of: lines[assignment.index]),
                  let inline = TOMLScan.inlineTable(value)
            else { continue }
            lines.remove(at: assignment.index)
            let trailing = lines.last == ""
            if trailing { lines.removeLast() }
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
            lines += (inline.comment.map { [$0] } ?? []) + ["[" + Self.written(full) + "]"] + inline.entries
            return SettingsDocument(text: lines.joined(separator: "\n") + (trailing ? "\n" : ""), exists: exists)
        }
        return nil
    }

    private struct Assignment {
        var index: Int
        var end: Int
        var table: [String]
        var key: [String]
        var indent: String
    }

    private static func assignments(in lines: [String]) -> [Assignment] {
        let outline = TOMLScan.outline(lines)
        return outline.assignments.compactMap { found in
            let header = outline.headers.last { $0.index < found.index }
            guard header?.isArray != true,
                  let (key, indent) = keyAssignment(in: lines[found.index])
            else { return nil }
            return Assignment(
                index: found.index, end: found.end, table: header?.path ?? [], key: key, indent: indent
            )
        }
    }
}

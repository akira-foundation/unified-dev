import Foundation

public enum OutputStyleIndex {
    public static func discover(
        home: String,
        project: String?,
        claudeHome: String? = nil,
        refusing refused: Set<AgentKind> = []
    ) -> [OutputStyle] {
        var found = OutputStyle.builtIns
        var known = Set(found.map(\.name))

        func add(_ styles: [OutputStyle]) {
            for style in styles where known.insert(style.name).inserted {
                found.append(style)
            }
        }

        if !refused.contains(.claudeCode) {
            add(styles(in: "\(claudeHome ?? "\(home)/.claude")/output-styles"))
        }
        if let project {
            add(styles(in: "\(project)/.claude/output-styles"))
        }

        let builtInCount = OutputStyle.builtIns.count
        return Array(found.prefix(builtInCount))
            + found.dropFirst(builtInCount).sorted { $0.name < $1.name }
    }

    static func styles(in directory: String) -> [OutputStyle] {
        SlashCommandIndex.walk(directory).compactMap { entry in
            guard entry.relative.hasSuffix(".md") else { return nil }
            let front = SlashCommandIndex.frontmatter(of: entry.path)
            let leaf = (entry.relative as NSString).lastPathComponent
            let stem = String(leaf.dropLast(3))
            guard let name = sanitised(front.name ?? stem) else { return nil }

            let detail = front.description.flatMap { $0.isEmpty ? nil : $0 }
            return OutputStyle(
                name: name,
                detail: detail ?? "A custom output style",
                isBuiltIn: false
            )
        }
    }

    static func sanitised(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 120 else { return nil }
        guard value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return value
    }
}

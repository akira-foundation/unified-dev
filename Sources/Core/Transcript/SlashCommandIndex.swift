import Foundation

public enum SlashCommandIndex {
    static let maximumDepth = 6
    static let maximumEntriesPerTree = 500
    static let frontmatterByteLimit = 8192
    static let documentationByteLimit = 64 * 1024
    static let detailLimit = 90

    public static func discover(
        home: String,
        project: String?,
        codexSkills: [SlashCommand]? = nil,
        codexHome: String? = nil,
        claudeHome: String? = nil,
        refusing refused: Set<AgentKind> = []
    ) -> [SlashCommand] {
        let claudeRoot = claudeHome ?? "\(home)/.claude"
        var byName: [String: SlashCommand] = [:]

        func add(_ commands: [SlashCommand]) {
            for command in commands { byName[command.name] = command }
        }

        add(builtIns)
        if !refused.contains(.claudeCode) {
            add(commands(in: "\(claudeRoot)/commands", namespace: nil, scope: .user))
            add(skills(in: "\(claudeRoot)/skills", namespace: nil, scope: .user))
            add(pluginEntries(claudeRoot: claudeRoot, project: project))
        }

        let codexRoot = codexHome ?? "\(home)/.codex"
        add(codexSkills?.filter { $0.scope != .project } ?? [])
        if codexSkills == nil, !refused.contains(.codex) {
            add(skills(in: "\(codexRoot)/skills/.system", namespace: nil, scope: .user))
            add(skills(in: "\(codexRoot)/skills", namespace: nil, scope: .user))
            add(skills(in: "\(home)/.agents/skills", namespace: nil, scope: .user))
        }

        if let project {
            add(commands(in: "\(project)/.claude/commands", namespace: nil, scope: .project))
            add(skills(in: "\(project)/.claude/skills", namespace: nil, scope: .project))
            if codexSkills == nil {
                add(skills(in: "\(project)/.codex/skills", namespace: nil, scope: .project))
                add(skills(in: "\(project)/.agents/skills", namespace: nil, scope: .project))
            }
        }

        add(codexSkills?.filter { $0.scope == .project } ?? [])

        return byName.values.sorted { $0.name < $1.name }
    }

    public static let builtIns: [SlashCommand] = [
        SlashCommand(name: "btw", detail: "Ask a side question while the main agent works", kind: .command, scope: .builtIn),
        SlashCommand(
            name: "close",
            detail: "Close this chat and start a fresh one",
            kind: .command,
            scope: .builtIn
        ),
        SlashCommand(
            name: "clear",
            detail: "Start a fresh chat here, keeping the previous conversation",
            kind: .command,
            scope: .builtIn
        ),
        SlashCommand(
            name: "code-review",
            detail: "Review the current diff, or a pull request, branch or path",
            kind: .command,
            scope: .builtIn
        ),
        SlashCommand(
            name: "compact",
            detail: "Summarise the conversation so far and continue with the summary",
            kind: .command,
            scope: .builtIn
        ),
        SlashCommand(
            name: "init",
            detail: "Write a CLAUDE.md describing this repository",
            kind: .command,
            scope: .builtIn
        ),
        SlashCommand(
            name: "pr-comments",
            detail: "Read and act on the review comments on this pull request",
            kind: .command,
            scope: .builtIn
        ),
        SlashCommand(
            name: "review",
            detail: "Review a pull request",
            kind: .command,
            scope: .builtIn
        ),
        SlashCommand(
            name: "security-review",
            detail: "Complete a security review of the pending changes on this branch",
            kind: .command,
            scope: .builtIn
        ),
        SlashCommand(
            name: "ultrareview",
            detail: "Run a cloud hosted multi agent review of this branch and print the findings",
            kind: .command,
            scope: .builtIn
        ),
    ]

    static func commands(
        in directory: String,
        namespace: String?,
        scope: SlashCommand.Scope
    ) -> [SlashCommand] {
        walk(directory).compactMap { entry in
            guard entry.relative.hasSuffix(".md") else { return nil }
            let leaf = String(entry.relative.dropLast(3)).replacing("/", with: ":")
            guard let name = qualified(leaf, namespace: namespace) else { return nil }
            let front = frontmatter(of: entry.path)
            return SlashCommand(
                name: name,
                detail: front.description ?? firstProseLine(of: entry.path),
                kind: .command,
                scope: scope,
                path: entry.path
            )
        }
    }

    static func skills(
        in directory: String,
        namespace: String?,
        scope: SlashCommand.Scope
    ) -> [SlashCommand] {
        skillFiles(in: directory).compactMap { entry in
            let folder = (entry.relative as NSString).deletingLastPathComponent
            guard !folder.isEmpty else { return nil }

            let front = frontmatter(of: entry.path)
            let leaf = front.name.flatMap(sanitised) ?? (folder as NSString).lastPathComponent
            guard let name = qualified(leaf, namespace: namespace) else { return nil }

            return SlashCommand(
                name: name,
                detail: front.description ?? "",
                kind: .skill,
                scope: scope,
                path: entry.path
            )
        }
    }

    static func skillFiles(in directory: String) -> [Entry] {
        guard isDirectory(directory) else { return [] }

        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        var found: [Entry] = []
        for name in names.sorted() {
            guard found.count < maximumEntriesPerTree else { break }
            guard !name.hasPrefix(".") else { continue }
            let folder = (directory as NSString).appendingPathComponent(name)
            guard isDirectory(folder) else { continue }
            let manifest = (folder as NSString).appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: manifest) else { continue }
            found.append(Entry(relative: "\(name)/SKILL.md", path: manifest))
        }
        return found
    }

    static func pluginEntries(claudeRoot: String, project: String?) -> [SlashCommand] {
        let enabled = enabledPluginKeys(claudeRoot: claudeRoot, project: project)
        guard !enabled.isEmpty else { return [] }
        let installed = installPaths(claudeRoot: claudeRoot)

        var found: [SlashCommand] = []
        for key in enabled.sorted() {
            guard let root = installed[key] else { continue }
            let namespace = pluginName(at: root) ?? String(key.prefix { $0 != "@" })
            guard let namespace = sanitised(namespace) else { continue }
            found += commands(
                in: "\(root)/commands",
                namespace: namespace,
                scope: .plugin(namespace)
            )
            found += skills(
                in: "\(root)/skills",
                namespace: namespace,
                scope: .plugin(namespace)
            )
        }
        return found
    }

    static func enabledPluginKeys(claudeRoot: String, project: String?) -> Set<String> {
        var flags: [String: Bool] = [:]

        var files = ["\(claudeRoot)/settings.json"]
        if let project {
            files.append("\(project)/.claude/settings.json")
            files.append("\(project)/.claude/settings.local.json")
        }

        for file in files {
            guard let object = json(at: file),
                  let plugins = object["enabledPlugins"] as? [String: Any] else { continue }
            for (key, value) in plugins {
                guard let enabled = value as? Bool else { continue }
                flags[key] = enabled
            }
        }

        return Set(flags.filter(\.value).map(\.key))
    }

    static func installPaths(claudeRoot: String) -> [String: String] {
        let file = "\(claudeRoot)/plugins/installed_plugins.json"
        guard let object = json(at: file),
              let plugins = object["plugins"] as? [String: Any] else { return [:] }

        var paths: [String: String] = [:]
        for (key, value) in plugins {
            guard let installs = value as? [[String: Any]] else { continue }
            let candidates = installs.compactMap { $0["installPath"] as? String }
            paths[key] = candidates.first { isDirectory($0) } ?? candidates.first
        }
        return paths
    }

    static func pluginName(at root: String) -> String? {
        guard let object = json(at: "\(root)/.claude-plugin/plugin.json") else { return nil }
        return (object["name"] as? String).flatMap(sanitised)
    }

    static func qualified(_ leaf: String, namespace: String?) -> String? {
        guard let leaf = sanitised(leaf) else { return nil }
        guard let namespace else { return leaf }
        return "\(namespace):\(leaf)"
    }

    static func sanitised(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 120 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.:")
        guard value.lowercased().unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return value
    }

    struct Frontmatter {
        var name: String?
        var description: String?
    }

    static func frontmatter(of path: String) -> Frontmatter {
        guard let head = head(of: path) else { return Frontmatter() }
        var lines = head.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return Frontmatter() }
        lines.removeFirst()

        var block: [String] = []
        var closed = false
        while let line = lines.first {
            lines.removeFirst()
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                closed = true
                break
            }
            block.append(line)
        }
        guard closed else { return Frontmatter() }

        return Frontmatter(
            name: value(of: "name", in: block).map(clean),
            description: value(of: "description", in: block).map(clean)
        )
    }

    static func value(of key: String, in block: [String]) -> String? {
        guard let index = block.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("\(key):")
        }) else { return nil }

        let line = block[index].trimmingCharacters(in: .whitespaces)
        var inline = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
        if inline == ">" || inline == ">-" || inline == "|" || inline == "|-" { inline = "" }
        guard inline.isEmpty else { return inline }

        var continuation: [String] = []
        for line in block[block.index(after: index)...] {
            guard line.hasPrefix(" ") || line.hasPrefix("\t") else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            continuation.append(trimmed)
        }
        return continuation.isEmpty ? nil : continuation.joined(separator: " ")
    }

    static func firstProseLine(of path: String) -> String {
        guard let head = head(of: path) else { return "" }
        var lines = head.components(separatedBy: .newlines)

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines.removeFirst()
            while let line = lines.first {
                lines.removeFirst()
                if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            return clean(String(trimmed.drop { $0 == "#" }))
        }
        return ""
    }

    public struct Documentation: Equatable, Sendable {
        public var lines: [String]
        public var truncated: Bool

        public init(lines: [String], truncated: Bool) {
            self.lines = lines
            self.truncated = truncated
        }
    }

    public static func documentation(of path: String, lines limit: Int, columns: Int) -> Documentation? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: documentationByteLimit), !data.isEmpty else {
            return nil
        }
        let text = String(decoding: data, as: UTF8.self)

        var lines = text.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines.removeFirst()
            while let line = lines.first {
                lines.removeFirst()
                if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            }
        }

        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        guard !lines.isEmpty else { return nil }

        let truncated = lines.count > limit
        let head = lines.prefix(limit).map { line -> String in
            let expanded = line.replacing("\t", with: "    ")
            return expanded.count > columns
                ? String(expanded.prefix(columns)) + "\u{2026}"
                : expanded
        }
        return Documentation(lines: head, truncated: truncated)
    }

    static func clean(_ text: String) -> String {
        var value = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing("\n", with: " ")
        if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
            value = String(value.dropFirst().dropLast())
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count > detailLimit ? String(value.prefix(detailLimit - 1)) + "\u{2026}" : value
    }

    struct Entry {
        var relative: String
        var path: String
    }

    static func walk(_ directory: String) -> [Entry] {
        guard isDirectory(directory) else { return [] }

        var found: [Entry] = []
        var visited: Set<String> = []

        func descend(_ path: String, relative: String, depth: Int) {
            guard depth <= maximumDepth, found.count < maximumEntriesPerTree else { return }
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard visited.insert(resolved).inserted else { return }

            let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            for name in names.sorted() {
                guard found.count < maximumEntriesPerTree else { return }
                guard !name.hasPrefix(".") else { continue }
                let child = (path as NSString).appendingPathComponent(name)
                let childRelative = relative.isEmpty ? name : "\(relative)/\(name)"
                if isDirectory(child) {
                    descend(child, relative: childRelative, depth: depth + 1)
                } else {
                    found.append(Entry(relative: childRelative, path: child))
                }
            }
        }

        descend(directory, relative: "", depth: 0)
        return found
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    static func head(of path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: frontmatterByteLimit), !data.isEmpty else {
            return nil
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    static func json(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

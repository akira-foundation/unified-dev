import Foundation

public enum WorkspaceBrowserURL {
    public static let file = "\(WorktreeScratch.generated)/url"

    static let byteLimit = 65_536

    public static func path(inWorktree worktree: String) -> String {
        (worktree as NSString).appendingPathComponent(file)
    }

    public static func resolve(
        written: String?, stated: String?, environment: [String: String], port: Int
    ) -> String {
        if let address = address(written) { return address }
        if let address = address(stated.map { expand($0, with: environment) }) { return address }
        return port > 0 ? "http://localhost:\(port)" : ""
    }

    public static func declared(
        settings: RepoSettings, environment: [String: String], port: Int
    ) -> String {
        resolve(written: nil, stated: settings.browserURL, environment: environment, port: port)
    }

    public static func read(
        worktree: String, settings: RepoSettings, environment: [String: String], port: Int
    ) -> String {
        resolve(
            written: written(atPath: path(inWorktree: worktree)), stated: settings.browserURL,
            environment: environment, port: port
        )
    }

    static func written(atPath path: String) -> String? {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard let data = try? handle.read(upToCount: byteLimit) else { return nil }
        return String(data: completeLines(of: data), encoding: .utf8)
    }

    static func completeLines(of data: Data) -> Data {
        guard data.count >= byteLimit else { return data }
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return Data() }
        return data[..<lastNewline]
    }

    static func address(_ raw: String?) -> String? {
        guard let line = raw?
            .components(separatedBy: .newlines)
            .lazy
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty })
        else { return nil }
        return line.contains("://") ? line : "http://" + line
    }

    static func expand(_ template: String, with environment: [String: String]) -> String {
        var result = ""
        var rest = Substring(template)

        while let dollar = rest.firstIndex(of: "$") {
            result += rest[rest.startIndex..<dollar]

            var cursor = rest.index(after: dollar)
            let braced = cursor < rest.endIndex && rest[cursor] == "{"
            if braced { cursor = rest.index(after: cursor) }

            var name = ""
            while cursor < rest.endIndex, isNameCharacter(rest[cursor]) {
                name.append(rest[cursor])
                cursor = rest.index(after: cursor)
            }

            let closed = !braced || (cursor < rest.endIndex && rest[cursor] == "}")
            if braced, closed { cursor = rest.index(after: cursor) }

            if !name.isEmpty, closed, let value = environment[name] {
                result += value
            } else {
                result += rest[dollar..<cursor]
            }
            rest = rest[cursor...]
        }

        return result + rest
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
    }
}

import Foundation

struct WorktreePathResolver {
    private static let mostGlobMatches = 4_000
    private static let mostEntriesWalked = 20_000

    private static let mostGlobbedComponents = 2

    let root: String
    let home: String
    private var given = ""

    init(worktree: String, home: String = NSHomeDirectory()) {
        let standard = URL(fileURLWithPath: worktree).standardized.path
        self.home = home
        root = WorktreePathResolver(root: "/", home: home).resolve(standard, from: "/") ?? standard
        given = standard
    }

    private init(root: String, home: String) {
        self.root = root
        self.home = home
        given = root
    }

    func contains(_ path: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    func resolve(_ path: String, from base: String) -> String? {
        var current = path.hasPrefix("/") ? "/" : base
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                current = Self.parent(of: current)
            default:
                let next = current == "/" ? "/\(component)" : "\(current)/\(component)"
                guard Self.exists(next) else {
                    current = next
                    continue
                }
                guard let physical = Self.physical(next) else { return nil }
                current = physical
            }
        }
        return current
    }

    func isDirectory(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    func staysInside(_ path: String, from bases: [String]) -> Bool {
        if path.hasPrefix("/"), !isUnder(path, given) && !isUnder(path, root) { return false }
        let tried = path.hasPrefix("/") ? Array(bases.prefix(1)) : bases
        return tried.allSatisfy { base in resolve(path, from: base).map(contains) == true }
    }

    func globStaysInside(_ pattern: String, from bases: [String]) -> Bool {
        let globbed = pattern.split(separator: "/").filter { $0.contains { "*?[".contains($0) } }
        guard !pattern.contains("**"), globbed.count <= Self.mostGlobbedComponents, staysInside(pattern, from: bases) else {
            return false
        }
        let tried = pattern.hasPrefix("/") ? Array(bases.prefix(1)) : bases
        return tried.allSatisfy { base in
            guard let matches = Self.matches(pattern.hasPrefix("/") ? pattern : "\(base)/\(pattern)") else { return false }
            return matches.filter(Self.namesAnEntry).allSatisfy { match in resolve(match, from: base).map(contains) == true }
        }
    }

    func holdsNoWayOut(below directory: String) -> Bool {
        guard directory != root else { return true }
        let url = URL(fileURLWithPath: directory)
        guard let walk = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: { _, _ in false }
        ) else { return false }
        var walked = 0
        for case let entry as URL in walk {
            walked += 1
            guard walked <= Self.mostEntriesWalked else { return false }
            guard (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true else { continue }
            guard let target = Self.physical(entry.path), contains(target) else { return false }
        }
        return true
    }

    private func isUnder(_ path: String, _ directory: String) -> Bool {
        let lexical = URL(fileURLWithPath: path).standardized.path
        return lexical == directory || lexical.hasPrefix(directory.hasSuffix("/") ? directory : directory + "/")
    }

    private static func namesAnEntry(_ match: String) -> Bool {
        let last = match.split(separator: "/").last
        return last != "." && last != ".."
    }

    private static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/" }
        return String(path[..<slash])
    }

    private static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    private static func physical(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func matches(_ pattern: String) -> [String]? {
        var found = glob_t()
        defer { globfree(&found) }
        let status = glob(pattern, GLOB_LIMIT, nil, &found)
        guard status == 0 else { return status == GLOB_NOMATCH ? [] : nil }
        let count = Int(found.gl_pathc)
        guard count <= mostGlobMatches, let paths = found.gl_pathv else { return nil }
        return (0..<count).compactMap { paths[$0].map { String(cString: $0) } }
    }
}

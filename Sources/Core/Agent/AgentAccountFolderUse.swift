import Foundation

public enum AgentAccountFolderUse: Sendable, Equatable {
    case free
    case held(pids: [Int32])
    case unknown

    public static func of(_ directory: URL, among processes: [ProcessVector]?) -> AgentAccountFolderUse {
        guard let processes else { return .unknown }
        let folders = [directory.path, directory.resolvingSymlinksInPath().path] + realPath(of: directory)
        let holders = processes.filter { process in
            process.strings?.contains { entry in folders.contains { names($0, in: entry) } } == true
                || process.paths.contains { path in folders.contains { TranscriptHome.isInside(settled: path, of: $0) } }
        }
        if !holders.isEmpty { return .held(pids: holders.map(\.pid)) }
        return processes.contains { $0.strings == nil } ? .unknown : .free
    }

    public func requireFree(path: String) throws {
        switch self {
        case .free: return
        case .held: throw AgentAccountError.folderInUse(path)
        case .unknown: throw AgentAccountError.folderUseUnknown(path)
        }
    }

    private static func realPath(of directory: URL) -> [String] {
        guard let resolved = realpath(directory.path, nil) else { return [] }
        defer { Darwin.free(resolved) }
        return [String(cString: resolved)]
    }

    private static func names(_ folder: String, in entry: String) -> Bool {
        var remaining = entry.startIndex..<entry.endIndex
        while let found = entry.range(of: folder, range: remaining) {
            guard found.upperBound < entry.endIndex, continuesName(entry[found.upperBound]) else { return true }
            remaining = found.upperBound..<entry.endIndex
        }
        return false
    }

    private static func continuesName(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
    }
}

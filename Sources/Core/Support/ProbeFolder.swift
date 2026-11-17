import Foundation

public enum ProbeFolderError: Error, Equatable, LocalizedError {
    case notMadeByAProbe(String)

    public var errorDescription: String? {
        switch self {
        case .notMadeByAProbe(let path):
            "The folder was not made by a probe, so it was left alone. Remove it if an older build left it: \(path)"
        }
    }
}

public enum ProbeFolder {
    public static let markerName = ".unifieddev-probe"

    public static func renew(_ root: URL) throws {
        let files = FileManager.default
        if files.fileExists(atPath: root.path) || isLink(root) {
            guard isMadeByAProbe(root) else { throw ProbeFolderError.notMadeByAProbe(root.path) }
            try files.removeItem(at: root)
        }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: markerName))
    }

    public static func failureToRenew(_ path: String) -> String? {
        do {
            try renew(URL(filePath: path, directoryHint: .isDirectory))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public static func discard(_ root: URL) {
        guard isMadeByAProbe(root) else { return }
        try? FileManager.default.removeItem(at: root)
    }

    static func isMadeByAProbe(_ root: URL) -> Bool {
        guard !isLink(root) else { return false }
        var isDirectory: ObjCBool = false
        let marker = root.appending(path: markerName).path
        return FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.fileExists(atPath: marker)
    }

    private static func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}

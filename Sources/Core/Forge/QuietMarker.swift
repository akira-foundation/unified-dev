import Foundation

struct QuietMarker: Sendable, Equatable {
    let file: URL
    let period: TimeInterval

    init(named name: String, period: TimeInterval, in folder: URL = FileManager.default.temporaryDirectory) {
        file = folder.appending(path: name)
        self.period = period
    }

    func isQuiet(at now: Date) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let written = attributes[.modificationDate] as? Date
        else { return false }
        return now.timeIntervalSince(written) < period
    }

    func remember() {
        FileManager.default.createFile(atPath: file.path, contents: Data(), attributes: [.posixPermissions: 0o600])
    }

    func forget() {
        try? FileManager.default.removeItem(at: file)
    }
}

import Foundation

struct QuietMarker: Sendable, Equatable {
    let file: URL
    let period: TimeInterval

    init(named name: String, period: TimeInterval, in folder: URL = FileManager.default.temporaryDirectory) {
        file = folder.appending(path: name)
        self.period = period
    }

    func age(at now: Date) -> TimeInterval? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let written = attributes[.modificationDate] as? Date
        else { return nil }
        return now.timeIntervalSince(written)
    }

    func isQuiet(at now: Date) -> Bool {
        age(at: now).map { $0 < period } ?? false
    }

    func remember(at moment: Date? = nil) {
        FileManager.default.createFile(atPath: file.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        guard let moment else { return }
        try? FileManager.default.setAttributes([.modificationDate: moment], ofItemAtPath: file.path)
    }

    func forget() {
        try? FileManager.default.removeItem(at: file)
    }
}

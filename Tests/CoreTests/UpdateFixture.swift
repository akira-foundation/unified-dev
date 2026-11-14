import Foundation
import Testing
@testable import Core

struct UpdateFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "unifieddev-update-test-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ text: String, to name: String) throws -> URL {
        let file = root.appending(path: name)
        try Data(text.utf8).write(to: file)
        return file
    }

    func signedApp(version: String, marker: String, in folder: String) async throws -> URL {
        let app = root.appending(path: folder).appending(path: UpdateInstaller.appName)
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appending(path: "Resources"), withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleExecutable": "UnifiedDev",
            "CFBundleIdentifier": "io.akira.unifieddev.update-test",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "1",
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appending(path: "Info.plist"))
        try FileManager.default.copyItem(
            at: URL(filePath: "/usr/bin/true"), to: contents.appending(path: "MacOS/UnifiedDev")
        )
        try Data(marker.utf8).write(to: contents.appending(path: "Resources/marker.txt"))

        try await Shell.check("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        return app
    }

    func designatedRequirement(of app: URL) async throws -> String {
        let result = try await Shell.check("/usr/bin/codesign", ["-d", "-r-", app.path])
        let text = result.stdout + "\n" + result.stderr
        let line = try #require(text.split(separator: "\n").first { $0.contains("designated => ") })
        return String(try #require(line.components(separatedBy: "designated => ").last))
    }

    func zip(_ app: URL) async throws -> URL {
        let archive = root.appending(path: "unified_dev_1.5.0_aarch64.zip")
        try await Shell.check("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, archive.path])
        return archive
    }

    func marker(in app: URL) throws -> String {
        try String(contentsOf: app.appending(path: "Contents/Resources/marker.txt"), encoding: .utf8)
    }

    func contents(of folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    func runReplacement(staged: URL, target: URL, requirement: String, log: URL) async throws -> Int32 {
        let finished = try ChildProcess("/usr/bin/true", [])
        await finished.awaitExit()

        let replacement = UpdateInstaller.Replacement(staged: staged, target: target, requirement: requirement, log: log)
        let process = try UpdateInstaller.launchReplacement(
            processID: finished.process.processIdentifier, replacement: replacement, reopen: "/usr/bin/true"
        )
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }
    }
}

import Foundation
import Testing
@testable import Core

extension Tag {
    @Tag static var git: Self
    @Tag static var destructive: Self
    @Tag static var agentProtocol: Self
    @Tag static var subprocess: Self
    @Tag static var security: Self
    @Tag static var persistence: Self
}

enum TestProcessScratch {
    static let root: String = {
        let path = Self.path(pid: getpid())
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        atexit {
            try? FileManager.default.removeItem(atPath: TestProcessScratch.path(pid: getpid()))
        }
        return path
    }()

    static func directory(_ prefix: String) -> String {
        let path = (root as NSString).appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    static func path(pid: pid_t) -> String {
        NSTemporaryDirectory() + "unifieddev-test-run-\(pid)"
    }
}

enum TestScratch {
    @TaskLocal static var directory: String?

    static func path(_ name: String) -> String {
        let root = directory ?? TestProcessScratch.directory("unscoped")
        return (root as NSString).appendingPathComponent(name)
    }

    static func unique(_ prefix: String) -> String {
        path("\(prefix)-\(UUID().uuidString)")
    }
}

actor RepoTemplate {
    static let shared = RepoTemplate()

    private var building: [String: Task<String, Error>] = [:]
    private let root = TestProcessScratch.directory("repo-templates")

    func path(defaultBranch: String) async throws -> String {
        if let inFlight = building[defaultBranch] { return try await inFlight.value }
        let root = root
        let index = building.count
        let task = Task { try await Self.build(defaultBranch: defaultBranch, at: root, index: index) }
        building[defaultBranch] = task
        return try await task.value
    }

    private static func build(defaultBranch: String, at root: String, index: Int) async throws -> String {
        let directory = (root as NSString)
            .appendingPathComponent("template-\(index)-\(defaultBranch)")
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )
        try await Shell.check("git", ["init", "-q", "-b", defaultBranch], cwd: directory)
        let config = (directory as NSString).appendingPathComponent(".git/config")
        let identity = """

            [user]
            \temail = test@unifieddev.local
            \tname = Unified Dev Test
            [commit]
            \tgpgsign = false
            [maintenance]
            \tauto = false

            """
        let existing = (try? String(contentsOfFile: config, encoding: .utf8)) ?? ""
        try (existing + identity).write(toFile: config, atomically: true, encoding: .utf8)

        try "hello\n".write(
            toFile: (directory as NSString).appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try await Shell.check("git", ["add", "-A"], cwd: directory)
        try await Shell.check("git", ["commit", "-q", "-m", "initial"], cwd: directory)
        return directory
    }
}

struct ScratchDirectoryTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: () async throws -> Void
    ) async throws {
        guard testCase != nil else {
            try await function()
            return
        }

        guard !TestWorkloadLimit.isHeld else {
            try await withDirectory(performing: function)
            return
        }
        try await TestWorkloadLimit.shared.acquire(ahead: test.timeLimit != nil)
        do {
            try Task.checkCancellation()
            try await TestWorkloadLimit.$isHeld.withValue(true) {
                try await withDirectory(performing: function)
            }
        } catch {
            await TestWorkloadLimit.shared.release()
            throw error
        }
        await TestWorkloadLimit.shared.release()
    }

    private func withDirectory(performing function: () async throws -> Void) async throws {
        let root = (TestProcessScratch.root as NSString)
            .appendingPathComponent("scratch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)

        do {
            try await TestScratch.$directory.withValue(root) {
                try await function()
            }
        } catch {
            await remove(root)
            throw error
        }
        await remove(root)
    }

    private func remove(_ path: String) async {
        for attempt in 0..<4 {
            try? FileManager.default.removeItem(atPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return }
            try? await Task.sleep(for: .milliseconds(25 * (attempt + 1)))
        }
        try? FileManager.default.removeItem(atPath: path)
    }
}

extension Trait where Self == ScratchDirectoryTrait {
    static var scratchDirectory: Self { Self() }
}

extension String {
    func contains(word: String) -> Bool {
        split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == "$") })
            .contains { $0 == word }
    }
}

final class Box<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) { self.value = value }
}

func makeTestStore(_ label: String = "store") throws -> Store {
    try Store(path: TestScratch.unique(label) + ".sqlite")
}

func activeSegmentID(_ store: Store, _ session: Session) async throws -> SessionSegmentID {
    try #require(try await store.activeSegment(sessionID: session.id)).id
}

func waitUntil(
    _ description: Comment,
    within timeout: Duration = .seconds(6),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @Sendable () async -> Bool
) async {
    let step = Duration.milliseconds(10)
    let attempts = max(1, Int(timeout / step))
    for _ in 0..<attempts {
        if await condition() { return }
        try? await Task.sleep(for: step)
    }
    Issue.record("timed out after \(timeout) waiting until \(description)", sourceLocation: sourceLocation)
}

struct TempRepo {
    let path: String

    init(defaultBranch: String = "main") async throws {
        let template = try await RepoTemplate.shared.path(defaultBranch: defaultBranch)
        path = TestScratch.unique("unifieddev-git")
        try FileManager.default.copyItem(atPath: template, toPath: path)
    }

    init(existing path: String) {
        self.path = path
    }

    func write(_ relative: String, _ contents: String) throws {
        let full = (path as NSString).appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true
        )
        try contents.write(toFile: full, atomically: true, encoding: .utf8)
    }

    func read(_ relative: String) -> String? {
        try? String(contentsOfFile: (path as NSString).appendingPathComponent(relative), encoding: .utf8)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(relative))
    }

    func commit(_ message: String) async throws {
        try await Shell.check("git", ["add", "-A"], cwd: path)
        try await Shell.check("git", ["commit", "-q", "-m", message], cwd: path)
    }

    func cleanUp() {
        for worktree in linkedWorktrees() {
            try? FileManager.default.removeItem(atPath: worktree)
        }
        removeManagedFolders()
        try? FileManager.default.removeItem(atPath: path)
    }

    func removeManagedFolders(under root: URL = WorkspaceManager.workspacesRoot) {
        let name = (path as NSString).lastPathComponent
        guard path.hasPrefix(TestProcessScratch.root), UUID(uuidString: String(name.suffix(36))) != nil else { return }
        let manager = FileManager.default
        let profileFolders = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in [root] + profileFolders {
            try? manager.removeItem(at: folder.appendingPathComponent(name, isDirectory: true))
        }
    }

    private func linkedWorktrees() -> [String] {
        guard let output = try? runGit(["worktree", "list", "--porcelain"]) else { return [] }
        let mine = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return output
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("worktree ") }
            .map { String($0.dropFirst("worktree ".count)) }
            .filter { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path != mine }
    }

    private func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        let child = try ChildProcess(process)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        child.waitForExit()
        return String(decoding: data, as: UTF8.self)
    }
}

func fixtureLines(_ name: String) throws -> [String] {
    let starts = [
        URL(fileURLWithPath: #filePath),
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath(),
    ]

    for start in starts {
        var directory = start.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("fixtures").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
                    .components(separatedBy: "\n")
                    .filter { $0.isEmpty == false }
            }
            directory = directory.deletingLastPathComponent()
        }
    }

    throw CocoaError(.fileNoSuchFile)
}

final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock(); lines.append(line); lock.unlock()
    }

    var joined: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}

extension WorkspaceSafetyReport: CustomTestStringConvertible {
    public var testDescription: String {
        isSafeToDiscard
            ? "safe to discard"
            : "would destroy " + losses.joined(separator: "; ")
    }
}

extension AgentEvent: CustomTestStringConvertible {
    public var testDescription: String {
        let body = String(decoding: raw.prefix(160), as: UTF8.self)
        return body.isEmpty ? "\(kind)" : "\(kind) \(body)"
    }
}

extension WorkspaceManager {
    @discardableResult
    func addRepository(at path: String) async throws -> Repo {
        try await addRepository(at: path, profileID: .initial)
    }
}

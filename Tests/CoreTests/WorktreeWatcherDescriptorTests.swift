import Foundation
import Testing
@testable import Core

@Suite("Worktree watcher descriptors", .serialized)
struct WorktreeWatcherDescriptorTests {
    private struct Fixture {
        let base: URL
        let roots: [String]

        init(roots count: Int) throws {
            let unique = FileManager.default.temporaryDirectory
                .appending(path: "ud-watch-descriptors-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: unique, withIntermediateDirectories: true)
            base = URL(filePath: WorktreeWatcher.resolve(unique.path), directoryHint: .isDirectory)
            let nested = base.appending(path: "a/b/c/d", directoryHint: .isDirectory)
            roots = try (0..<count).map { index in
                let root = nested.appending(path: "root-\(index)", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                return root.path
            }
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: base)
        }

        func descriptorsInside() -> Int {
            let prefix = base.path
            return (0..<4096).filter { descriptor in
                var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                guard fcntl(Int32(descriptor), F_GETPATH, &path) != -1 else { return false }
                return String(cString: path).hasPrefix(prefix)
            }.count
        }
    }

    private static func standardInput() -> ino_t? {
        var status = stat()
        return fstat(STDIN_FILENO, &status) == 0 ? status.st_ino : nil
    }

    @Test("streams are created without watching the roots themselves")
    func flagsLeaveTheRootsUnwatched() {
        for fileEvents in [true, false] {
            let flags = WorktreeWatcher.creationFlags(fileEvents: fileEvents)
            #expect(flags & FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot) == 0)
            #expect((flags & FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents) != 0) == fileEvents)
        }
    }

    @Test("a live stream over many roots holds no descriptor inside them")
    func watchingHoldsNoDescriptorPerRoot() throws {
        let fixture = try Fixture(roots: 30)
        defer { fixture.cleanUp() }
        let watcher = WorktreeWatcher(onFilesChanged: { _ in }, onChange: { _ in })
        defer { watcher.stop() }

        watcher.watch(roots: fixture.roots)

        #expect(watcher.isWatching)
        #expect(fixture.descriptorsInside() == 0)
    }

    @Test("rebuilding the streams for changing roots neither leaks descriptors nor touches standard input")
    func rebuildsDoNotLeak() throws {
        let fixture = try Fixture(roots: 12)
        defer { fixture.cleanUp() }
        let watcher = WorktreeWatcher(onFilesChanged: { _ in }, onChange: { _ in })
        let input = try #require(Self.standardInput())

        watcher.watch(roots: fixture.roots)
        for round in 0..<60 {
            watcher.watch(roots: Array(fixture.roots.dropFirst(round % fixture.roots.count)))
        }
        watcher.watch(roots: fixture.roots)
        let watching = watcher.isWatching
        let heldWhileWatching = fixture.descriptorsInside()
        watcher.stop()

        #expect(watching)
        #expect(heldWhileWatching == 0)
        #expect(fixture.descriptorsInside() == 0)
        #expect(Self.standardInput() == input)
    }

    @Test("the lowest closed descriptor is reopened on the null device")
    func reopensTheLowestClosedDescriptor() throws {
        var lowest: Int32 = -1
        var reopened = false
        for _ in 0..<50 where !reopened {
            lowest = open("/dev/null", O_RDONLY)
            try #require(lowest >= 0)
            close(lowest)
            reopened = WorktreeWatcher.reopenNullDevice(ifClosed: lowest)
        }
        defer { if reopened { close(lowest) } }

        var status = stat()
        var null = stat()
        #expect(reopened)
        #expect(fstat(lowest, &status) == 0 && stat("/dev/null", &null) == 0 && status.st_rdev == null.st_rdev)
    }

    @Test("a descriptor that is open is left alone")
    func leavesAnOpenDescriptorAlone() {
        #expect(!WorktreeWatcher.reopenNullDevice(ifClosed: STDOUT_FILENO))
        #expect(fcntl(STDOUT_FILENO, F_GETFD) != -1)
    }

    @Test("a closed descriptor that is not the lowest free one is not taken over")
    func doesNotTakeOverAnotherNumber() throws {
        let holder = open("/dev/null", O_RDONLY)
        try #require(holder >= 0)
        let high = fcntl(holder, F_DUPFD, 3000)
        close(holder)
        try #require(high >= 3000)
        close(high)

        let reopened = WorktreeWatcher.reopenNullDevice(ifClosed: high)

        #expect(!reopened)
        #expect(fcntl(high, F_GETFD) == -1)
    }
}

import Foundation
import Testing
@testable import Core

@Suite("Reading the arguments and environment of processes")
struct ProcessVectorsTests {
    @Test func theEnvironmentOfThisProcessIsAmongWhatIsRead() throws {
        let vectors = try #require(ProcessVectors.ofThisUser())
        let own = try #require(vectors.first { $0.pid == ProcessInfo.processInfo.processIdentifier })
        let readsEnvironment = own.strings?.contains { $0.hasPrefix("PATH=") } == true

        #expect(readsEnvironment)
    }

    @Test func thisProcessIsNotAmongTheOthers() throws {
        let others = try #require(ProcessVectors.ofOtherProcesses())
        let includesItself = others.contains { $0.pid == ProcessInfo.processInfo.processIdentifier }

        #expect(!includesItself)
    }

    @Test func aDescriptionNeverCarriesWhatTheProcessHolds() {
        let vector = ProcessVector(pid: 7, strings: ["TOKEN=secret-value"])

        #expect(!String(describing: vector).contains("secret-value"))
        #expect(!String(reflecting: vector).contains("secret-value"))
        #expect(!String(describing: [vector]).contains("secret-value"))
    }

    @Test func aMirrorNeverReachesWhatTheProcessHolds() {
        let vector = ProcessVector(pid: 7, strings: ["TOKEN=secret-value"])
        var dumped = ""

        dump(vector, to: &dumped)

        #expect(!dumped.contains("secret-value"))
        #expect(Mirror(reflecting: vector).children.map(\.label) == ["pid"])
    }

    @Test func aRunningProcessIsNotAZombieAndAReapedOneCountsAsGone() async throws {
        let sleeper = try ChildProcess("/bin/sleep", ["30"])
        let whileRunning = ProcessVectors.isZombie(sleeper.process.processIdentifier)
        await sleeper.stop()

        #expect(!whileRunning)
        #expect(ProcessVectors.isZombie(sleeper.process.processIdentifier))
    }

    @Test func aChildNobodyHasWaitedForIsAZombie() async throws {
        var spawned: pid_t = 0
        let path = strdup("/usr/bin/true")
        defer { free(path) }
        let environment: [UnsafeMutablePointer<CChar>?] = [nil]
        let status = posix_spawn(&spawned, "/usr/bin/true", nil, nil, [path, nil], environment)
        try #require(status == 0)
        let child = spawned
        defer { waitpid(child, nil, 0) }

        var attempts = 0
        while !ProcessVectors.isZombie(child), attempts < 1_000 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(ProcessVectors.isZombie(child))
    }

    @Test func onlyTheUnreadableAreReadAgainAndOnlyWhileAnyRemain() {
        var calls: [Int32: Int] = [:]
        var pauses = 0
        let vectors = ProcessVectors.settle(
            pids: [1, 2],
            rereads: 10,
            read: { pid in
                calls[pid, default: 0] += 1
                return pid == 1 || calls[pid, default: 0] > 1 ? .strings(["x"]) : .unreadable
            },
            isZombie: { _ in false },
            pause: { pauses += 1 }
        )

        #expect(vectors.map(\.pid) == [1, 2])
        #expect(calls == [1: 1, 2: 2])
        #expect(pauses == 1)
    }

    @Test func aProcessThatBecomesReadableOnARereadIsRead() {
        var reads = 0
        let vectors = ProcessVectors.settle(
            pids: [7],
            read: { _ in
                reads += 1
                return reads < 3 ? .unreadable : .strings(["sleep"])
            },
            isZombie: { _ in false },
            pause: {}
        )

        #expect(vectors == [ProcessVector(pid: 7, strings: ["sleep"])])
    }

    @Test func aProcessThatNeverBecomesReadableIsReportedUnreadable() {
        let vectors = ProcessVectors.settle(
            pids: [7], rereads: 3, read: { _ in .unreadable }, isZombie: { _ in false }, pause: {}
        )

        #expect(vectors == [ProcessVector(pid: 7, strings: nil)])
    }

    @Test func aProcessThatExitsOrDiesWhileBeingReadIsDropped() {
        let gone = ProcessVectors.settle(pids: [7], read: { _ in .gone }, isZombie: { _ in false }, pause: {})
        let zombie = ProcessVectors.settle(pids: [7], read: { _ in .unreadable }, isZombie: { _ in true }, pause: {})

        #expect(gone.isEmpty)
        #expect(zombie.isEmpty)
    }

    @Test func theArgumentCountAndEveryStringAreRead() {
        var bytes: [UInt8] = [2, 0, 0, 0]
        bytes += Array("/bin/sleep".utf8) + [0, 0, 0]
        bytes += Array("sleep".utf8) + [0]
        bytes += Array("120".utf8) + [0]
        bytes += Array("A=1".utf8) + [0, 0]

        #expect(ProcessVectors.strings(inArguments: bytes[...]) == ["/bin/sleep", "sleep", "120", "A=1"])
    }
}

import Foundation
import Testing
@testable import Core

@Suite("Discarding a reservation an agent may still hold", .tags(.persistence), .scratchDirectory)
struct AgentAccountReservationDiscardTests {
    @Test func aReservationGoesOnceTheProcessHoldingItHasExited() async throws {
        let reservation = try AgentAccountCreation.reserve(
            provider: .claudeCode, label: "Client", existing: [], support: URL(filePath: TestScratch.unique("support"), directoryHint: .isDirectory)
        )
        let holder = ProcessVector(pid: 7, strings: ["X=\(reservation.plan.directory.path)"])
        let reads = Reads()

        let discarded = await reservation.discardOnceReleased(pause: .zero, processes: {
            reads.next() < 2 ? [holder] : []
        })

        #expect(discarded)
        #expect(!FileManager.default.fileExists(atPath: reservation.plan.directory.path))
    }

    @Test func aReservationStillHeldAfterEveryAttemptIsKept() async throws {
        let reservation = try AgentAccountCreation.reserve(
            provider: .claudeCode, label: "Client", existing: [], support: URL(filePath: TestScratch.unique("support"), directoryHint: .isDirectory)
        )
        let holder = ProcessVector(pid: 7, strings: ["X=\(reservation.plan.directory.path)"])
        let reads = Reads()

        let discarded = await reservation.discardOnceReleased(attempts: 3, pause: .zero, processes: {
            _ = reads.next()
            return [holder]
        })

        #expect(!discarded)
        #expect(reads.next() == 3)
        #expect(FileManager.default.fileExists(atPath: reservation.plan.directory.path))
    }

    @Test func aReservationIsKeptWhenTheProcessesCannotBeRead() throws {
        let reservation = try AgentAccountCreation.reserve(
            provider: .claudeCode, label: "Client", existing: [], support: URL(filePath: TestScratch.unique("support"), directoryHint: .isDirectory)
        )

        #expect(!reservation.discard(processes: { nil }))
        #expect(FileManager.default.fileExists(atPath: reservation.plan.directory.path))
    }

    @Test func aReservationOneProcessCannotBeReadIsKept() throws {
        let reservation = try AgentAccountCreation.reserve(
            provider: .claudeCode, label: "Client", existing: [], support: URL(filePath: TestScratch.unique("support"), directoryHint: .isDirectory)
        )

        #expect(!reservation.discard(processes: { [ProcessVector(pid: 7, strings: nil)] }))
        #expect(FileManager.default.fileExists(atPath: reservation.plan.directory.path))
    }

    @Test func aReservationNamingAFolderOutsideTheAccountsIsKept() throws {
        let support = URL(filePath: TestScratch.unique("support"), directoryHint: .isDirectory)
        let made = try AgentAccountCreation.reserve(
            provider: .claudeCode, label: "Client", existing: [], support: support
        ).plan
        let elsewhere = URL(filePath: TestScratch.unique("elsewhere"), directoryHint: .isDirectory)
            .appending(path: made.id.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let stray = AgentAccountReservation(
            plan: AgentAccountCreation(provider: made.provider, label: made.label, id: made.id, directory: elsewhere),
            support: support
        )

        #expect(!stray.discard(processes: { [] }))
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
    }

    @Test func aReservationTheGateRefusesIsNotRetried() async throws {
        let support = URL(filePath: TestScratch.unique("support"), directoryHint: .isDirectory)
        let made = try AgentAccountCreation.reserve(
            provider: .claudeCode, label: "Client", existing: [], support: support
        ).plan
        let elsewhere = URL(filePath: TestScratch.unique("elsewhere"), directoryHint: .isDirectory)
            .appending(path: made.id.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let stray = AgentAccountReservation(
            plan: AgentAccountCreation(provider: made.provider, label: made.label, id: made.id, directory: elsewhere),
            support: support
        )
        let reads = Reads()
        var discarded = true

        let elapsed = await ContinuousClock().measure {
            discarded = await stray.discardOnceReleased(attempts: 3, pause: .seconds(1), processes: {
                _ = reads.next()
                return []
            })
        }

        #expect(!discarded)
        #expect(reads.next() == 0)
        #expect(elapsed < .seconds(1))
    }
}

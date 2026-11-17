import Foundation
import Testing
@testable import Core

@Suite("Keeping the starting points read for a while", .scratchDirectory)
struct StartingPointReaderTests {
    private typealias Double = StartingPointGitHubDouble

    @Test("pressing + again within two minutes reuses the last reading, and at two minutes reads again")
    func reusesAFreshReading() async {
        let clock = ReadingClock()
        let readings = StartingPointReader.Readings(now: { clock.now })
        let request = StartingPointReadingRequest(repoPath: TestScratch.unique("suggestions-cache"), asksGitHub: true)
        let asked = AskedCommands()
        await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            _ = await StartingPointReader.load(request, from: readings)
        }
        #expect(await asked.commands.count == 3)

        clock.advance(.seconds(119))
        let kept = await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            await StartingPointReader.load(request, from: readings)
        }
        #expect(await asked.commands.count == 3)
        #expect(kept?.issues.map(\.number) == [34])

        clock.advance(.seconds(1))
        await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            _ = await StartingPointReader.load(request, from: readings)
        }
        #expect(await asked.commands.count > 3)
    }

    @Test("a reading taken without GitHub is not reused once GitHub can be asked")
    func keyedByWhetherGitHubWasAsked() async {
        let readings = StartingPointReader.Readings()
        let path = TestScratch.unique("suggestions-key")
        let asked = AskedCommands()
        await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            _ = await StartingPointReader.load(StartingPointReadingRequest(repoPath: path, asksGitHub: false), from: readings)
            _ = await StartingPointReader.load(StartingPointReadingRequest(repoPath: path, asksGitHub: true), from: readings)
        }
        #expect(await asked.commands.count == 3)
    }

    @Test("a reading is not shown to another GitHub login the project's directory is routed to")
    func keyedByLogin() async {
        let readings = StartingPointReader.Readings()
        let request = StartingPointReadingRequest(repoPath: TestScratch.unique("suggestions-login"), asksGitHub: true)
        let routed = GitHubLogin.unresolved(directory: URL(fileURLWithPath: request.repoPath))
        let asked = AskedCommands()
        await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            _ = await GitHub.$loginResolverOverride.withValue({ _ in nil }) {
                await StartingPointReader.load(request, from: readings)
            }
            _ = await GitHub.$loginResolverOverride.withValue({ $0 == request.repoPath ? routed : nil }) {
                await StartingPointReader.load(request, from: readings)
            }
        }
        #expect(await asked.commands.count == 6)
    }

    @Test("leaving the pane in the middle of a read still keeps the whole reading for the next visit")
    func cancelledCallerKeepsTheReading() async {
        let readings = StartingPointReader.Readings()
        let request = StartingPointReadingRequest(repoPath: TestScratch.unique("suggestions-cancelled"), asksGitHub: true)
        let asked = AskedCommands()
        let gate = ReadingGate()
        let held: GitHubCommand = { arguments, _ in
            await asked.record(arguments)
            await gate.pass()
            return ShellResult(status: 0, stdout: Double.answer(arguments), stderr: "")
        }
        let task = Task {
            await GitHub.$commandOverride.withValue(held) {
                await StartingPointReader.load(request, from: readings)
            }
        }
        await gate.reached()
        task.cancel()
        await gate.open()
        _ = await task.value
        let next = await GitHub.$commandOverride.withValue(Double.answering(asked)) {
            await StartingPointReader.load(request, from: readings)
        }
        #expect(next?.issues.map(\.number) == [34])
        #expect(next?.pullRequests.reviewRequested.map(\.number) == [21])
        #expect(await asked.commands.count == 3)
    }
}

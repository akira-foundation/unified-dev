import Testing
import Foundation
@testable import Core

@Suite("Pull request facts the auto fix reads")
struct PullRequestAutoFixFactsTests {
    private func decode(_ json: String) throws -> PullRequest {
        try GitHub.decodePullRequest(from: Data(json.utf8))
    }

    @Test("the author and the fork flag are read from gh")
    func authorAndFork() throws {
        let read = try decode(#"{"number":1,"author":{"login":"owner"},"isCrossRepository":true,"statusCheckRollup":[]}"#)
        #expect(read.author == "owner")
        #expect(read.isFromFork == true)
    }

    @Test("gh saying nothing leaves both unknown")
    func missing() throws {
        let read = try decode(#"{"number":1,"statusCheckRollup":[]}"#)
        #expect(read.author == nil)
        #expect(read.isFromFork == nil)
    }

    @Test("a required failure beside a running check is still unfinished")
    func failureBesideRunning() throws {
        let read = try decode(#"""
        {"number":1,"statusCheckRollup":[
          {"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"FAILURE","isRequired":true},
          {"__typename":"CheckRun","name":"b","status":"IN_PROGRESS","conclusion":""}
        ]}
        """#)
        #expect(read.checks == .failing)
        #expect(read.hasUnfinishedChecks == true)
    }

    @Test("every check concluded is finished")
    func finished() throws {
        let read = try decode(#"""
        {"number":1,"statusCheckRollup":[
          {"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"FAILURE","isRequired":true}
        ]}
        """#)
        #expect(read.hasUnfinishedChecks == false)
    }

    @Test("gh is asked for what the decision reads")
    func fieldsAsked() {
        #expect(GitHub.fields.split(separator: ",").contains("author"))
        #expect(GitHub.fields.split(separator: ",").contains("isCrossRepository"))
    }

    @Test("checks the app could not read leave every check fact unknown")
    func unreadableChecks() throws {
        let read = try GitHub.decodePullRequest(from: Data(#"{"number":1}"#.utf8), checksReadable: false)
        #expect(read.hasUnfinishedChecks == nil)
        #expect(read.hasFixableCheckFailure == nil)
    }

    @Test("a failing conclusion is fixable", arguments: ["FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE"])
    func fixable(conclusion: String) throws {
        let read = try decode(rollup(conclusion: conclusion))
        #expect(read.hasFixableCheckFailure == true)
    }

    @Test("a run that was stopped rather than failed is not", arguments: ["CANCELLED", "STALE", "ACTION_REQUIRED", "SUCCESS"])
    func notFixable(conclusion: String) throws {
        let read = try decode(rollup(conclusion: conclusion))
        #expect(read.hasFixableCheckFailure == false)
    }

    @Test("gh's real shape carries no isRequired, and a failure still reads as failing")
    func withoutIsRequired() throws {
        let read = try decode(rollup(conclusion: "FAILURE"))
        #expect(read.checks == .failing)
        #expect(read.hasUnfinishedChecks == false)
    }

    private func rollup(conclusion: String) -> String {
        #"{"number":1,"statusCheckRollup":[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"\#(conclusion)"}]}"#
    }

    @Test("gh leaving out the rollup leaves every check fact unknown")
    func absentRollup() throws {
        let read = try decode(#"{"number":1}"#)
        #expect(read.hasUnfinishedChecks == nil)
        #expect(read.hasFixableCheckFailure == nil)
    }
}

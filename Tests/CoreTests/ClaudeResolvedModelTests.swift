import Foundation
import Testing
@testable import Core

@Suite("The version an alias of Claude Code really runs", .tags(.agentProtocol), .scratchDirectory)
struct ClaudeResolvedModelTests {
    private let work = AgentAccountHome(
        provider: .claudeCode, id: AgentAccountID("work"),
        directory: URL(filePath: "/accounts/claudeCode/work"), isDefault: false
    )
    private let client = AgentAccountHome(
        provider: .claudeCode, id: AgentAccountID("client"),
        directory: URL(filePath: "/accounts/claudeCode/client"), isDefault: false
    )

    private func model(_ id: String, unavailable: String? = nil) -> AgentModel {
        AgentModel(id: id, displayName: id, unavailable: unavailable)
    }

    private func version(listed: [AgentModel] = [], reported: [String: String] = [:]) -> String? {
        ClaudeResolvedModel.version(ofAlias: "opus", listed: listed, reported: reported)
    }

    @Test("the account's own list names the version of its family")
    func readsTheAccountList() {
        #expect(ClaudeResolvedModel.version(
            ofAlias: "fable", listed: [model("claude-fable-5-1[1m]")], reported: [:]
        ) == "5.1")
    }

    @Test("what the CLI reported outranks an older version the account's list still carries")
    func theReportComesFirst() {
        let listed = [model("claude-opus-4-6"), model("claude-opus-4-7")]

        #expect(version(listed: listed, reported: ["opus": "claude-opus-5-5"]) == "5.5")
    }

    @Test("the newest listed entry answers when the CLI reported nothing for the family")
    func fallsBackToTheNewestListed() {
        let listed = [model("claude-opus-5-1"), model("claude-opus-5-5")]

        #expect(version(listed: listed, reported: ["fable": "claude-fable-5-1"]) == "5.5")
    }

    @Test("a stored model the alias cannot be read from names no version, rather than the list's newest", arguments: [
        "claude-sonnet-5", "claude-3-5-sonnet-20241022", "us.anthropic.claude-opus-4-5-v1:0",
    ])
    func anUnreadableStoredModelNamesNoVersion(stored: String) {
        #expect(version(listed: [model("claude-opus-5-5")], reported: ["opus": stored]) == nil)
    }

    @Test("a dated id of a whole version does not outrank a newer point release")
    func aDateIsNotAMinorVersion() {
        let listed = [model("claude-opus-4-20250514"), model("claude-opus-4-5-20250929")]

        #expect(version(listed: listed) == "4.5")
    }

    @Test("an entry the account cannot use never names a version", arguments: [
        "claude-opus-5-5", "cc-update-required-1",
    ])
    func refusesAnUnusableEntry(id: String) {
        #expect(version(listed: [model(id, unavailable: "Update first")]) == nil)
    }

    @Test("an alias that resolved to another family has no version of its own")
    func refusesAnotherFamily() {
        #expect(version(reported: ["opus": "claude-sonnet-5"]) == nil)
    }

    @Test("with no source there is no version")
    func saysNothingWithoutASource() {
        #expect(version() == nil)
    }

    @Test("reads a version out of every shape of id", arguments: [
        ("claude-opus-5", "5"),
        ("claude-opus-5-5", "5.5"),
        ("claude-opus-5-5[1m]", "5.5"),
        ("claude-opus-4-8-20260101", "4.8"),
        ("claude-opus-5-20260101", "5"),
    ])
    func readsTheVersion(id: String, expected: String) {
        #expect(ClaudeResolvedModel.version(of: id, alias: "opus") == expected)
    }

    @Test("an id that names no version answers nothing", arguments: [
        "opus", "opus-5-5", "claude-opus", "claude-3-opus-20240229",
    ])
    func readsNoVersion(id: String) {
        #expect(ClaudeResolvedModel.version(of: id, alias: "opus") == nil)
    }

    @Test("the picker keeps the alias as its id and adds the version to the name")
    func offersTheAliasWithItsVersion() {
        let offered = ClaudeModelCatalog.offered(
            read: [model("claude-fable-5-1[1m]")],
            reported: ["opus": "claude-opus-5-5"]
        )

        let names = Dictionary(uniqueKeysWithValues: offered.map { ($0.id, $0.displayName) })
        #expect(names["fable"] == "Fable 5.1")
        #expect(names["opus"] == "Opus 5.5")
        #expect(names["sonnet"] == "Sonnet")
        #expect(names["haiku"] == "Haiku")
    }

    @Test("offering an already offered list keeps one row per alias, and its version")
    func offeringTwiceKeepsTheVersion() {
        let first = ClaudeModelCatalog.offered(read: [model("claude-fable-5-1")])
        let second = ClaudeModelCatalog.offered(read: first, including: "fable", reported: ["opus": "claude-opus-5-5"])

        #expect(second.filter { $0.id == "fable" }.map(\.displayName) == ["Fable 5.1"])
        #expect(second.filter { $0.id == "opus" }.map(\.displayName) == ["Opus 5.5"])
    }

    @Test("what an alias resolved to is kept per account")
    func keepsObservationsPerAccount() async throws {
        let store = try makeTestStore("resolved")

        await ClaudeResolvedModel.record(requested: "opus", reported: "claude-opus-5-5", cliVersion: "2.1.322", account: work, in: store)
        await ClaudeResolvedModel.record(requested: "opus", reported: "claude-opus-5", cliVersion: "2.1.322", account: client, in: store)
        await ClaudeResolvedModel.record(requested: "sonnet", reported: "claude-sonnet-5", cliVersion: "2.1.322", account: nil, in: store)

        #expect(await ClaudeResolvedModel.reported(account: work, in: store) == ["opus": "claude-opus-5-5"])
        #expect(await ClaudeResolvedModel.reported(account: client, in: store) == ["opus": "claude-opus-5"])
        #expect(await ClaudeResolvedModel.reported(account: nil, in: store) == ["sonnet": "claude-sonnet-5"])
    }

    @Test("a later observation replaces the earlier one")
    func aNewVersionReplacesTheOldOne() async throws {
        let store = try makeTestStore("resolved")

        await ClaudeResolvedModel.record(requested: "opus", reported: "claude-opus-5", cliVersion: "2.1.322", account: work, in: store)
        await ClaudeResolvedModel.record(requested: "opus", reported: "claude-opus-5-5", cliVersion: "2.1.322", account: work, in: store)

        #expect(await ClaudeResolvedModel.reported(account: work, in: store) == ["opus": "claude-opus-5-5"])
    }

    @Test("only an alias answered with a real id of its family is recorded", arguments: [
        ("claude-opus-5-1", "claude-opus-5-1"),
        ("opus", "opus"),
        ("opus", "claude-sonnet-5"),
        ("opus", "definitely-not-a-model"),
    ])
    func recordsOnlyAResolvedAlias(requested: String, reported: String) async throws {
        let store = try makeTestStore("resolved")

        await ClaudeResolvedModel.record(requested: requested, reported: reported, cliVersion: "2.1.322", account: work, in: store)

        #expect(await ClaudeResolvedModel.reported(account: work, in: store).isEmpty)
    }

    @Test("forgetting an account forgets what it resolved to, and no other account's")
    func forgettingAnAccountForgetsItsObservations() async throws {
        let store = try makeTestStore("resolved")
        try await store.add(AgentAccountRow(
            id: work.id, provider: .claudeCode, directory: work.directory.path, label: "Work",
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))
        for alias in ClaudeModelCatalog.builtIn.map(\.id) {
            await ClaudeResolvedModel.record(requested: alias, reported: "claude-\(alias)-5", cliVersion: "2.1.322", account: work, in: store)
        }
        await ClaudeResolvedModel.record(ClaudeAliasAnswers(probed: ["sonnet": "claude-sonnet-5-5"]), cliVersion: nil, account: work, in: store)
        await ClaudeResolvedModel.record(requested: "opus", reported: "claude-opus-5", cliVersion: "2.1.322", account: client, in: store)
        await ClaudeResolvedModel.record(ClaudeAliasAnswers(probed: ["sonnet": "claude-sonnet-5-5"]), cliVersion: nil, account: client, in: store)

        try await store.forgetAgentAccount(work.id)
        await ClaudeResolvedModel.record(ClaudeAliasAnswers(probed: ["opus": "claude-opus-5-9"]), cliVersion: "2.1.322", account: work, in: store)

        #expect(await ClaudeResolvedModel.reported(account: work, in: store) == ["opus": "claude-opus-5-9"])
        #expect(await ClaudeResolvedModel.reported(account: client, in: store)
            == ["opus": "claude-opus-5", "sonnet": "claude-sonnet-5-5"])
    }

    @Test("a probe of the same CLI version never replaces what a turn observed")
    func aTurnOutranksAProbeOfItsVersion() async throws {
        let store = try makeTestStore("resolved")

        await ClaudeResolvedModel.record(ClaudeAliasAnswers(probed: ["opus": "claude-opus-5-5"]), cliVersion: "2.1.322", account: work, in: store)
        await ClaudeResolvedModel.record(requested: "opus", reported: "claude-opus-4-1", cliVersion: "2.1.322", account: work, in: store)
        await ClaudeResolvedModel.record(ClaudeAliasAnswers(probed: ["opus": "claude-opus-5-5"]), cliVersion: "2.1.322 (Claude Code)", account: work, in: store)

        #expect(await ClaudeResolvedModel.reported(account: work, in: store) == ["opus": "claude-opus-4-1"])
    }

    @Test("a probe of a newer CLI replaces a turn the older one ran, and a pin replaces any turn")
    func aNewVersionOrAPinReplacesATurn() async throws {
        let store = try makeTestStore("resolved")

        await ClaudeResolvedModel.record(requested: "opus", reported: "claude-opus-5-5", cliVersion: "2.1.309", account: work, in: store)
        await ClaudeResolvedModel.record(ClaudeAliasAnswers(probed: ["opus": "claude-opus-5-6"]), cliVersion: "2.1.322", account: work, in: store)
        #expect(await ClaudeResolvedModel.reported(account: work, in: store) == ["opus": "claude-opus-5-6"])

        await ClaudeResolvedModel.record(requested: "opus", reported: "claude-opus-5-7", cliVersion: "2.1.322", account: work, in: store)
        await ClaudeResolvedModel.record(ClaudeAliasAnswers(pinned: ["opus": "claude-opus-4-1-20250805"]), cliVersion: "2.1.322", account: work, in: store)
        #expect(await ClaudeResolvedModel.reported(account: work, in: store) == ["opus": "claude-opus-4-1-20250805"])

        await ClaudeResolvedModel.record(ClaudeAliasAnswers(probed: ["opus": "claude-opus-5-8"]), cliVersion: "2.1.322", account: work, in: store)
        #expect(await ClaudeResolvedModel.reported(account: work, in: store) == ["opus": "claude-opus-5-8"])
    }

    @Test("a probe whose CLI version is unknown answers an alias no turn has run, and leaves one a turn has")
    func anUnknownVersionOnlyFillsTheGaps() async throws {
        let store = try makeTestStore("resolved")

        await ClaudeResolvedModel.record(requested: "sonnet", reported: "claude-sonnet-4-5", cliVersion: "2.1.309", account: work, in: store)
        await ClaudeResolvedModel.record(
            ClaudeAliasAnswers(probed: ["opus": "claude-opus-5-5", "sonnet": "claude-sonnet-5-5"]), cliVersion: nil, account: work, in: store
        )

        #expect(await ClaudeResolvedModel.reported(account: work, in: store) == ["opus": "claude-opus-5-5", "sonnet": "claude-sonnet-4-5"])
    }

    @Test("a turn whose init names no CLI version still outranks a probe")
    func anUnversionedTurnOutranksAProbe() async throws {
        let store = try makeTestStore("resolved")

        await ClaudeResolvedModel.record(requested: "opus", reported: "claude-opus-4-1", cliVersion: "", account: work, in: store)
        await ClaudeResolvedModel.record(ClaudeAliasAnswers(probed: ["opus": "claude-opus-5-5"]), cliVersion: "2.1.322", account: work, in: store)

        #expect(await ClaudeResolvedModel.reported(account: work, in: store) == ["opus": "claude-opus-4-1"])
    }

    @Test("a probe and a turn of the same CLI recorded at once always leave the turn's answer", .timeLimit(.minutes(1)))
    func aProbeNeverLandsUnderATurnsMarker() async throws {
        let store = try makeTestStore("resolved")
        let accounts = (0..<200).map {
            AgentAccountHome(
                provider: .claudeCode, id: AgentAccountID("race-\($0)"),
                directory: URL(filePath: "/accounts/claudeCode/race-\($0)"), isDefault: false
            )
        }

        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask {
                    await ClaudeResolvedModel.record(
                        ClaudeAliasAnswers(probed: ["opus": "claude-opus-5-5"]), cliVersion: "2.1.322", account: account, in: store
                    )
                }
                group.addTask {
                    await ClaudeResolvedModel.record(
                        requested: "opus", reported: "claude-opus-4-1", cliVersion: "2.1.322", account: account, in: store
                    )
                }
            }
        }
        var probeWon: [String] = []
        for account in accounts where await ClaudeResolvedModel.reported(account: account, in: store)["opus"] != "claude-opus-4-1" {
            probeWon.append(account.id.rawValue)
        }

        #expect(probeWon.isEmpty)
    }

    @Test("a pin to a model id the picker cannot read is kept, and the alias then names no version")
    func anUnreadablePinShowsNoVersion() async throws {
        let store = try makeTestStore("resolved")
        let pin = "us.anthropic.claude-opus-4-5-v1:0"

        await ClaudeResolvedModel.record(ClaudeAliasAnswers(probed: ["opus": "claude-opus-5-5"]), cliVersion: "2.1.322", account: work, in: store)
        await ClaudeResolvedModel.record(ClaudeAliasAnswers(pinned: ["opus": pin]), cliVersion: "2.1.322", account: work, in: store)
        let reported = await ClaudeResolvedModel.reported(account: work, in: store)

        #expect(reported == ["opus": pin])
        #expect(ClaudeResolvedModel.version(ofAlias: "opus", listed: [model("claude-opus-5-5")], reported: reported) == nil)
    }

    @Test("a probe keeps only an id of the alias's own family, per account")
    func keepsProbesPerAccount() async throws {
        let store = try makeTestStore("resolved")

        await ClaudeResolvedModel.record(
            ClaudeAliasAnswers(probed: ["opus": "claude-opus-5-5", "sonnet": "claude-haiku-5-5", "haiku": "haiku"]),
            cliVersion: nil, account: work, in: store
        )
        await ClaudeResolvedModel.record(ClaudeAliasAnswers(probed: ["opus": "claude-opus-4-8"]), cliVersion: nil, account: client, in: store)

        #expect(await ClaudeResolvedModel.reported(account: work, in: store) == ["opus": "claude-opus-5-5"])
        #expect(await ClaudeResolvedModel.reported(account: client, in: store) == ["opus": "claude-opus-4-8"])
    }
}

import Testing
import Foundation
@testable import Core

@Suite("Agent account panel")
struct AgentAccountPanelTests {
    private let locale = Locale(identifier: "en_GB")
    private let utc = TimeZone(identifier: "UTC")!

    private func panel(
        _ standings: [AgentAccountStanding],
        for provider: AgentKind = .claudeCode,
        orphans: [AgentAccountHome] = [],
        codex: CodexAuthStorageMode = .file
    ) -> AgentAccountPanel {
        AgentAccountPanel.make(
            provider: provider, standings: standings, orphans: orphans, codexStorageMode: codex,
            locale: locale, timeZone: utc
        )
    }

    private func standing(
        _ home: AgentAccountHome,
        identity: AgentAccountIdentity = AgentAccountIdentity(),
        report: AgentAccountLiveness.CliReport = .unanswered,
        exists: Bool = true,
        doubt: String? = nil
    ) -> AgentAccountStanding {
        AgentAccountStanding(
            home: home, identity: identity, cliReport: report, isolationDoubt: doubt, directoryExists: exists
        )
    }

    private func value(_ label: String, in row: AgentAccountPanel.Row) -> String? {
        row.fields.first { $0.label == label }?.value
    }

    @Test func aRowShowsEmailPlanExpiryAndSessionAndNothingElse() throws {
        let identity = AgentAccountIdentity(
            email: "me@client.com", displayName: "Me", organisationName: "Client Ltd", plan: "Max 5x",
            expiresAt: Date(timeIntervalSince1970: 1_792_000_000)
        )
        let made = panel([standing(AccountFixture.work, identity: identity, report: .claimsSession)])
        let row = try #require(made.rows.first)

        #expect(row.fields.map(\.label) == ["Email", "Plan", "Expires", "Session"])
        #expect(value("Email", in: row) == "me@client.com")
        #expect(value("Plan", in: row) == "Max 5x")
        let expires = try #require(value("Expires", in: row))
        #expect(expires.contains("14 Oct 2026") && expires.contains("17:46"))
        #expect(value("Session", in: row) == "Signed in")
    }

    @Test func aFieldThatIsMissingSaysUnknown() throws {
        let row = try #require(panel([standing(AccountFixture.work)]).rows.first)

        #expect(value("Email", in: row) == "unknown")
        #expect(value("Plan", in: row) == "unknown")
        #expect(value("Expires", in: row) == "unknown")
        #expect(row.fields.filter { !$0.isKnown }.map(\.label) == ["Email", "Plan", "Expires"])
    }

    @Test func aSessionTheCliDidNotAnswerForIsNotConfirmedRatherThanPresentOrAbsent() throws {
        let unanswered = try #require(panel([standing(AccountFixture.work, report: .unanswered)]).rows.first)
        let signedIn = try #require(panel([standing(AccountFixture.work, report: .claimsSession)]).rows.first)
        let signedOut = try #require(panel([standing(AccountFixture.work, report: .claimsNoSession)]).rows.first)

        #expect(value("Session", in: unanswered) == "Not confirmed")
        #expect(value("Session", in: signedIn) == "Signed in")
        #expect(value("Session", in: signedOut) == "Not signed in")
    }

    @Test func theDisplayNameAndTheOrganisationNeverReachAField() throws {
        let identity = AgentAccountIdentity(email: "me@client.com", displayName: "Secret Name", organisationName: "Secret Org")
        let row = try #require(panel([standing(AccountFixture.work, identity: identity)]).rows.first)
        let everything = row.fields.map(\.value).joined(separator: " ") + (row.note ?? "")

        #expect(!everything.contains("Secret"))
    }

    @Test func aCredentialFileOnDiskNeverReachesARow() throws {
        let support = URL(filePath: TestScratch.unique("support"), directoryHint: .isDirectory)
        let made = AgentAccountCreation.plan(provider: .claudeCode, label: "Client", existing: [], support: support)
        try AgentAccountCreation.prepareDirectory(of: made.home)
        try Data(#"{"claudeAiOauth":{"accessToken":"sk-ant-secret","refreshToken":"rt-secret","subscriptionType":"max","expiresAt":1792000000000}}"#.utf8)
            .write(to: made.home.credentialPath)
        let identity = AgentAccountIdentity.read(
            made.home, identity: nil, credential: try Data(contentsOf: made.home.credentialPath)
        )
        let row = try #require(panel([standing(made.home, identity: identity)]).rows.first)
        let everything = row.fields.map(\.value).joined(separator: " ") + (row.note ?? "") + row.title

        #expect(identity.plan == "Max")
        #expect(!everything.contains("secret"))
    }

    @Test func aDefaultAccountWhoseFolderIsNotThereIsNotSetUp() throws {
        let row = try #require(panel([standing(AccountFixture.defaultCodex, exists: false)], for: .codex).rows.first)

        #expect(value("Session", in: row) == "Not set up")
    }

    @Test func aFolderNobodyAddedAnAccountForShowsAsAnUnfinishedSignInWithARemoval() throws {
        let orphan = AccountFixture.extra("client")
        let made = panel([standing(AccountFixture.defaultClaude)], orphans: [orphan])
        let row = try #require(made.rows.last)

        #expect(made.rows.count == 2)
        #expect(row.isUnfinished && row.title == "client")
        #expect(value("Session", in: row) == "Sign-in did not finish")
        #expect(row.removal?.title == "Remove client?")
        #expect(row.warns)
    }

    @Test func anUnfinishedSignInOfAnotherAgentIsNotShownHere() {
        let orphan = AccountFixture.extra("client", provider: .codex)

        #expect(panel([standing(AccountFixture.defaultClaude)], orphans: [orphan]).rows.count == 1)
    }

    @Test func anAccountNamedByItsLabelShowsTheLabelAsItsTitle() throws {
        let labelled = AgentAccountHome(
            provider: .claudeCode, id: AgentAccountID("client"),
            directory: URL(filePath: "/support/claudeCode/client", directoryHint: .isDirectory),
            isDefault: false, label: "Client"
        )

        #expect(try #require(panel([standing(labelled)]).rows.first).title == "Client")
    }

    @Test func aFolderThatIsGoneIsSaidSoAndWarns() throws {
        let row = try #require(panel([standing(AccountFixture.work, exists: false)]).rows.first)

        #expect(value("Session", in: row) == "Folder missing")
        #expect(row.note == "This account's folder is no longer on this Mac.")
        #expect(row.warns)
    }

    @Test func anAccountWhoseIsolationIsNotGuaranteedSaysSoWithTheRostersDoubt() throws {
        let doubt = "Codex keeps its login in the system keychain here, which a separate directory does not keep apart."
        let lab = AccountFixture.extra("lab", provider: .codex)
        let row = try #require(panel([standing(lab, doubt: doubt)], for: .codex, codex: .keyring).rows.first)

        #expect(row.note == "Unified Dev does not guarantee this account stays separate for Codex. \(doubt)")
        #expect(row.warns)
    }

    @Test func anAccountWhoseIsolationIsGuaranteedHasNoNote() throws {
        let row = try #require(panel([standing(AccountFixture.work)]).rows.first)

        #expect(row.note == nil)
        #expect(!row.warns)
    }

    @Test func theDefaultAccountCannotBeRemovedAndItsDoubtIsNotRepeatedOnIt() throws {
        let row = try #require(panel([standing(AccountFixture.defaultCodex, doubt: "Some doubt.")], for: .codex).rows.first)

        #expect(row.removal == nil)
        #expect(row.note == "Used wherever a project has not chosen another account.")
        #expect(!row.warns)
    }

    @Test func anAccountTheAppMadeCanBeRemovedAndTheWarningNamesIt() throws {
        let identity = AgentAccountIdentity(email: "me@client.com")
        let row = try #require(panel([standing(AccountFixture.work, identity: identity)]).rows.first)

        #expect(row.removal?.title == "Remove me@client.com?")
    }

    @Test func onlyTheRowsOfTheAskedAgentAreShownDefaultFirst() {
        let standings = [
            standing(AccountFixture.defaultClaude), standing(AccountFixture.work),
            standing(AccountFixture.defaultCodex), standing(AccountFixture.extra("lab", provider: .codex)),
        ]

        #expect(panel(standings, for: .claudeCode).rows.map(\.id) == [AccountFixture.defaultClaude.id, AccountFixture.work.id])
        #expect(panel(standings, for: .codex).rows.map(\.id) == [AccountFixture.defaultCodex.id, AccountFixture.extra("lab", provider: .codex).id])
    }

    @Test func twoAccountsOfTheSameEmailAreToldApartByTheSameNamesTheComposerUses() {
        let identity = AgentAccountIdentity(email: "a@b.c")
        let standings = [
            standing(AccountFixture.defaultClaude, identity: identity), standing(AccountFixture.work, identity: identity),
        ]

        #expect(panel(standings).rows.map(\.title) == AgentAccountOptions.make(
            choices: AgentAccountChoices(project: [.claudeCode: AccountFixture.defaultClaude.id]), standings: standings
        ).groups.flatMap(\.entries).map(\.title))
    }

    @Test func anAgentWithNoAccountAtAllHasNoRows() {
        #expect(panel([standing(AccountFixture.defaultClaude)], for: .cursor).rows.isEmpty)
    }

    @Test func aRowTitleIsTheNameTheComposerLineUses() throws {
        let identity = AgentAccountIdentity(email: "me@client.com")
        let standings = [standing(AccountFixture.defaultClaude), standing(AccountFixture.work, identity: identity)]
        let line = AgentAccountLine.make(
            choice: AgentAccountChoice.resolve(provider: .claudeCode, project: AccountFixture.work.id, standings: standings),
            provider: .claudeCode, standings: standings
        )

        let work = try #require(panel(standings).rows.first { $0.id == AccountFixture.work.id })
        #expect(work.title == line.title)
    }
}

@Suite("Agent account offer")
struct AgentAccountOfferTests {
    @Test(arguments: [AgentKind.claudeCode, .codex, .grok])
    func anAgentTheAppCanIsolateAndCheckIsOffered(provider: AgentKind) {
        #expect(AgentAccountOffer.make(for: provider, codexStorageMode: .file) == .available)
    }

    @Test(arguments: [AgentKind.antigravity, .cursor, .openCode])
    func anAgentWithNoDirectoryOfItsOwnIsNotOfferedAndSaysWhyWithTheRostersOwnWords(provider: AgentKind) throws {
        let doubt = try #require(AgentAccountRoster.isolationDoubt(for: provider, codexStorageMode: .file))

        #expect(AgentAccountOffer.make(for: provider, codexStorageMode: .file) == .unavailable(
            reason: "Unified Dev cannot add another \(provider.label) account. \(doubt)"
        ))
    }

    @Test func eachRefusedAgentGivesTheReasonMeasuredForItself() {
        #expect(AgentAccountRoster.isolationDoubt(for: .antigravity, codexStorageMode: .file)
            == "Antigravity keeps its login under HOME alone, and a separate HOME would move every other setting the agent reads.")
        #expect(AgentAccountRoster.isolationDoubt(for: .cursor, codexStorageMode: .file)
            == "Cursor can move its configuration to another directory, but its login is not documented to move with it.")
        #expect(AgentAccountRoster.isolationDoubt(for: .openCode, codexStorageMode: .file)
            == "Whether a directory of its own keeps an OpenCode login apart has not been measured yet.")
    }

    @Test func codexIsNotOfferedWhereItKeepsItsLoginInTheKeychain() throws {
        let doubt = try #require(AgentAccountRoster.isolationDoubt(for: .codex, codexStorageMode: .keyring))

        #expect(AgentAccountOffer.make(for: .codex, codexStorageMode: .keyring) == .unavailable(
            reason: "Unified Dev cannot add another Codex account. \(doubt)"
        ))
    }

    @Test(arguments: AgentKind.allCases)
    func everyAgentWhoseLoginKeepsApartHasAQuestionToAskIt(provider: AgentKind) {
        guard AgentAccountRoster.isolationDoubt(for: provider, codexStorageMode: .file) == nil else { return }
        #expect(AgentAccountLiveness.canAsk(about: provider))
    }

    @Test func todaysOfferPerAgentIsClaudeCodexAndGrok() {
        let offered = AgentKind.allCases.filter { AgentAccountOffer.make(for: $0, codexStorageMode: .file).isAvailable }

        #expect(Set(offered) == [.claudeCode, .codex, .grok])
    }
}

@Suite("Agent account standing answers")
struct AgentAccountStandingAnswersTests {
    @Test func aRememberedAnswerReplacesTheUnansweredOneOfTheSameAccount() {
        let plain = AccountFixture.standing(AccountFixture.work)

        let answered = plain.reporting([AccountFixture.work.id: .claimsSession])

        #expect(answered.cliReport == .claimsSession)
        #expect(answered.home == plain.home && answered.identity == plain.identity)
    }

    @Test func anAccountWithNoRememberedAnswerKeepsItsOwn() {
        let plain = AccountFixture.standing(AccountFixture.work)

        #expect(plain.reporting([AccountFixture.personal.id: .claimsSession]).cliReport == .unanswered)
    }
}

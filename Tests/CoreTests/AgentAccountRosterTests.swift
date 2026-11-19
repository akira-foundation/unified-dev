import Testing
import Foundation
@testable import Core

private actor AskedHomes {
    private(set) var ids: [AgentAccountID] = []

    func record(_ id: AgentAccountID) {
        ids.append(id)
    }
}

@Suite("Agent account roster")
struct AgentAccountRosterTests {
    private let support = URL(filePath: "/support")
    private let user = URL(filePath: "/Users/someone")

    private var defaultClaude: AgentAccountHome { AgentAccountHome.defaultHome(for: .claudeCode, home: user)! }
    private var defaultCodex: AgentAccountHome { AgentAccountHome.defaultHome(for: .codex, home: user)! }
    private var defaultGrok: AgentAccountHome { AgentAccountHome.defaultHome(for: .grok, home: user)! }

    private var workRow: AgentAccountRow {
        AgentAccountRow(
            id: AgentAccountID("work"),
            provider: .claudeCode,
            directory: AgentAccountHomes.directory(for: AgentAccountID("work"), provider: .claudeCode, support: support).path,
            label: "Work"
        )
    }

    private let readsNothing: @Sendable (AgentAccountHome) -> (identity: Data?, credential: Data?) = { _ in (nil, nil) }
    private let allExist: @Sendable (AgentAccountHome) -> Bool = { _ in true }
    private let claimsNothing: @Sendable (AgentAccountHome) async -> AgentAccountLiveness.CliReport = { _ in .unanswered }

    private func claudeIdentity(email: String) -> Data {
        Data(#"{"oauthAccount":{"emailAddress":"\#(email)"}}"#.utf8)
    }

    @Test func theRosterIsTheDefaultDirectoryPlusTheOnesTheAppMade() async {
        let standings = await AgentAccountRoster.standings(
            rows: [workRow], defaults: [defaultClaude], read: readsNothing,
            codexStorageMode: .file, exists: allExist, report: claimsNothing
        )
        #expect(standings.map(\.home.id) == [defaultClaude.id, workRow.id])
    }

    @Test func aRowBecomesAHomeThatIsNotTheDefault() async {
        let standings = await AgentAccountRoster.standings(
            rows: [workRow], defaults: [], read: readsNothing, codexStorageMode: .file, exists: allExist, report: claimsNothing
        )
        #expect(standings[0].home.directory.path == workRow.directory)
        #expect(standings[0].home.provider == .claudeCode)
        let isDefault = standings[0].home.isDefault
        #expect(!isDefault)
    }

    @Test func twoAccountsReportingTheSameEmailStayTwoStandings() async {
        let same = claudeIdentity(email: "a@b.c")
        let standings = await AgentAccountRoster.standings(
            rows: [workRow], defaults: [defaultClaude], read: { _ in (same, nil) },
            codexStorageMode: .file, exists: allExist, report: claimsNothing
        )
        #expect(standings.count == 2)
        #expect(standings.allSatisfy { $0.identity.email == "a@b.c" })
        #expect(Set(standings.map(\.home.directory)).count == 2)
    }

    @Test func eachStandingIsReadFromItsOwnHome() async {
        let work = workRow
        let standings = await AgentAccountRoster.standings(
            rows: [work], defaults: [defaultClaude],
            read: { home in
                (self.claudeIdentity(email: home.isDefault ? "me@home" : "me@work"), nil)
            },
            codexStorageMode: .file, exists: allExist, report: claimsNothing
        )
        #expect(standings.map(\.identity.email) == ["me@home", "me@work"])
    }

    @Test func theCliReportIsCarriedAsItWasGivenWithoutBecomingAYesOrNo() async {
        let reports: [AgentAccountID: AgentAccountLiveness.CliReport] = [
            defaultClaude.id: .claimsSession,
            workRow.id: .claimsNoSession,
            defaultCodex.id: .unanswered,
        ]
        let standings = await AgentAccountRoster.standings(
            rows: [workRow], defaults: [defaultClaude, defaultCodex], read: readsNothing,
            codexStorageMode: .file, exists: allExist, report: { reports[$0.id] ?? .unanswered }
        )
        #expect(standings.map(\.cliReport) == [.claimsSession, .unanswered, .claimsNoSession])
    }

    @Test func everyHomeIsAskedAndTheOrderSurvivesAnswersArrivingOutOfOrder() async {
        let rows = (0..<6).map {
            AgentAccountRow(id: AgentAccountID("r\($0)"), provider: .claudeCode, directory: "/support/r\($0)")
        }
        let standings = await AgentAccountRoster.standings(
            rows: rows, defaults: [defaultClaude], read: readsNothing, codexStorageMode: .file, exists: allExist,
            report: { home in
                let delay = home.id.rawValue == "r0" ? 80 : 1
                try? await Task.sleep(for: .milliseconds(delay))
                return .claimsSession
            }
        )
        #expect(standings.map(\.home.id.rawValue) == ["default.claudeCode", "r0", "r1", "r2", "r3", "r4", "r5"])
        #expect(standings.allSatisfy { $0.cliReport == .claimsSession })
    }

    @Test(arguments: [AgentKind.claudeCode, .codex])
    func anAccountWhoseDirectoryIsGoneIsNeverAskedAndReadsAsUnanswered(provider: AgentKind) async {
        let gone = AgentAccountRow(id: AgentAccountID("gone"), provider: provider, directory: "/support/gone")
        let asked = AskedHomes()
        let standings = await AgentAccountRoster.standings(
            rows: [gone], defaults: [], read: readsNothing, codexStorageMode: .file,
            exists: { _ in false },
            report: { home in
                await asked.record(home.id)
                return .claimsSession
            }
        )
        let askedIDs = await asked.ids
        #expect(askedIDs.isEmpty)
        #expect(standings.map(\.cliReport) == [.unanswered])
    }

    @Test func onlyTheAccountsThatExistAreAsked() async {
        let gone = AgentAccountRow(id: AgentAccountID("gone"), provider: .claudeCode, directory: "/support/gone")
        let asked = AskedHomes()
        let standings = await AgentAccountRoster.standings(
            rows: [gone, workRow], defaults: [defaultClaude], read: readsNothing, codexStorageMode: .file,
            exists: { $0.id != gone.id },
            report: { home in
                await asked.record(home.id)
                return .claimsSession
            }
        )
        let askedIDs = await asked.ids
        #expect(Set(askedIDs) == [defaultClaude.id, workRow.id])
        #expect(standings.map(\.cliReport) == [.claimsSession, .unanswered, .claimsSession])
    }

    @Test func aRowWhoseIdCollidesWithADefaultIsIgnoredAndTheDefaultWins() async {
        let collision = AgentAccountRow(
            id: defaultClaude.id, provider: .claudeCode, directory: "/support/impostor", label: "Impostor"
        )
        let standings = await AgentAccountRoster.standings(
            rows: [collision, workRow], defaults: [defaultClaude], read: readsNothing,
            codexStorageMode: .file, exists: allExist, report: claimsNothing
        )
        #expect(standings.map(\.home.id) == [defaultClaude.id, workRow.id])
        #expect(standings[0].home == defaultClaude)
    }

    @Test func codexIsolationIsNotGuaranteedWhenTheStorageModeIsNotFile() async {
        let standings = await AgentAccountRoster.standings(
            rows: [], defaults: [defaultCodex], read: readsNothing, codexStorageMode: .keyring, exists: allExist, report: claimsNothing
        )
        #expect(standings[0].isolationIsGuaranteed == false)
        #expect(standings[0].isolationDoubt?.isEmpty == false)
    }

    @Test func codexIsolationIsGuaranteedInFileMode() async {
        let standings = await AgentAccountRoster.standings(
            rows: [], defaults: [defaultCodex], read: readsNothing, codexStorageMode: .file, exists: allExist, report: claimsNothing
        )
        #expect(standings[0].isolationIsGuaranteed == true)
        #expect(standings[0].isolationDoubt == nil)
    }

    @Test func claudeIsolationDoesNotDependOnTheCodexStorageMode() async {
        let standings = await AgentAccountRoster.standings(
            rows: [], defaults: [defaultClaude], read: readsNothing, codexStorageMode: .keyring, exists: allExist, report: claimsNothing
        )
        #expect(standings[0].isolationIsGuaranteed == true)
        #expect(standings[0].isolationDoubt == nil)
    }

    @Test func grokIsolationIsGuaranteedBecauseGrokHomeWasMeasured() async {
        let standings = await AgentAccountRoster.standings(
            rows: [], defaults: [defaultGrok], read: readsNothing, codexStorageMode: .file, exists: allExist, report: claimsNothing
        )
        #expect(standings[0].isolationIsGuaranteed == true)
        #expect(standings[0].isolationDoubt == nil)
    }

    @Test func aRowWhoseDirectoryIsGoneIsStillListedWithAnEmptyIdentity() async {
        let standings = await AgentAccountRoster.standings(
            rows: [workRow], defaults: [], read: readsNothing, codexStorageMode: .file, exists: allExist, report: claimsNothing
        )
        #expect(standings.count == 1)
        #expect(standings[0].identity == AgentAccountIdentity())
    }

    @Test func everyDirectoryTheSpendIndexerReadsIsOnTheRoster() async {
        let indexed = TranscriptSources.sources(provider: user)
        let standings = await AgentAccountRoster.standings(
            rows: [workRow],
            defaults: SpendAccounts.defaultHomes(home: user),
            read: readsNothing, codexStorageMode: .file, exists: allExist, report: claimsNothing
        )
        let listed = Set(standings.map { $0.home.directory.standardizedFileURL.path })
        let missing = indexed.filter { !listed.contains($0.home.standardizedFileURL.path) }
        #expect(!indexed.isEmpty)
        #expect(missing.isEmpty)
    }

    @Test func theSpendBoardsDefaultAccountsAreTheDirectoriesALaunchWithNoAccountRunsUnder() {
        #expect(SpendAccounts.defaultHomes(home: user).map(\.directory.path)
            == [defaultClaude.directory.path, defaultCodex.directory.path])
    }
}

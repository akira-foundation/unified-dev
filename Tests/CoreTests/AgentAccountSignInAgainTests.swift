import Testing
import Foundation
@testable import Core

@Suite("Agent account sign in again")
struct AgentAccountSignInAgainTests {
    private let directory = URL(filePath: "/tmp/support/AgentAccounts/claudeCode/client", directoryHint: .isDirectory)

    private func standing(
        provider: AgentKind = .claudeCode,
        isDefault: Bool = false,
        report: AgentAccountLiveness.CliReport = .claimsNoSession,
        doubt: String? = nil,
        directoryExists: Bool = true
    ) -> AgentAccountStanding {
        AgentAccountStanding(
            home: AgentAccountHome(provider: provider, id: AgentAccountID("client"), directory: directory, isDefault: isDefault),
            identity: AgentAccountIdentity(),
            cliReport: report,
            isolationDoubt: doubt,
            directoryExists: directoryExists
        )
    }

    private func row(_ standing: AgentAccountStanding) throws -> AgentAccountPanel.Row {
        try #require(AgentAccountPanel.make(
            provider: standing.home.provider, standings: [standing], codexStorageMode: .file
        ).rows.first)
    }

    @Test func anAccountThatLostItsSessionOffersASignIn() throws {
        #expect(try row(standing(report: .claimsNoSession)).offersSignInAgain)
    }

    @Test func anAccountTheCliStillCallsSignedInOffersOneBecauseThatCanBeWrong() throws {
        #expect(try row(standing(report: .claimsSession)).offersSignInAgain)
    }

    @Test(arguments: [AgentKind.claudeCode, AgentKind.codex, AgentKind.grok])
    func everyAgentWithAFolderOfItsOwnOffersIt(provider: AgentKind) throws {
        #expect(try row(standing(provider: provider)).offersSignInAgain)
    }

    @Test func theDefaultAccountKeepsItsOwnSignInAndOffersNoOther() throws {
        #expect(try !row(standing(isDefault: true)).offersSignInAgain)
    }

    @Test func aMissingFolderHasNothingToSignInToAgain() throws {
        #expect(try !row(standing(directoryExists: false)).offersSignInAgain)
    }

    @Test func aLoginTheFolderDoesNotKeepApartIsNeverOffered() throws {
        let doubt = "Codex keeps its login in the system keychain here, which a separate directory does not keep apart."

        #expect(try !row(standing(provider: .codex, doubt: doubt)).offersSignInAgain)
    }

    @Test func anUnfinishedSignInIsNotAnAccountToSignInToAgain() throws {
        let panel = AgentAccountPanel.make(
            provider: .claudeCode, standings: [], orphans: [standing().home], codexStorageMode: .file
        )

        #expect(try !#require(panel.rows.first).offersSignInAgain)
    }

    @Test func theRecoveryOfAnAccountThatIsNotOfferedTheButtonDoesNotPromiseASignIn() {
        let text = AgentAccountSignOut.recovery(provider: .claudeCode, standing: standing(directoryExists: false))

        #expect(text.contains("cannot sign this account in again"))
        #expect(!text.contains("Sign in to it again"))
    }

    @Test func theRecoveryOfAnAccountThatCanSignInSaysSo() {
        let text = AgentAccountSignOut.recovery(provider: .claudeCode, standing: standing())

        #expect(text.contains("Sign in to it again"))
    }

    @Test func theRecoveryOfTheDefaultAccountSaysSignInBecauseSettingsHasItsOwn() {
        let text = AgentAccountSignOut.recovery(provider: .claudeCode, standing: standing(isDefault: true))

        #expect(text.contains("Sign in to it again"))
    }

    @Test func aRowThatPointsAtTheCliOwnFolderIsNeverOffered() {
        let userHome = URL(filePath: "/Users/ada", directoryHint: .isDirectory)
        let own = AgentAccountStanding(
            home: AgentAccountHome(
                provider: .claudeCode, id: AgentAccountID("client"),
                directory: userHome.appending(path: ".claude", directoryHint: .isDirectory), isDefault: false
            ),
            identity: AgentAccountIdentity(), cliReport: .claimsNoSession, isolationDoubt: nil
        )

        #expect(!AgentAccountSignInAgain.isOffered(for: own, userHome: userHome))
        #expect(AgentAccountSignInAgain.isOffered(for: standing(), userHome: userHome))
    }

    @Test func onlyAnOfferedRowNamesTheFolderToSignIn() throws {
        #expect(try row(standing()).signInAgainHome?.directory == directory)
        #expect(try row(standing(isDefault: true)).signInAgainHome == nil)
    }

    @Test func theSignInRunsInTheAccountsOwnFolderWithACleanEnvironment() throws {
        let home = try #require(try row(standing()).signInAgainHome)

        let variables = AgentAccountEnvironment.login(
            launching: home.provider, as: home,
            inheriting: ["CLAUDE_CONFIG_DIR": "/somewhere/else", "ANTHROPIC_API_KEY": "inherited"],
            userHome: URL(filePath: "/Users/ada")
        )

        #expect(variables["CLAUDE_CONFIG_DIR"] == directory.path)
        #expect(variables["ANTHROPIC_API_KEY"] == nil)
    }

    @Test func theNoticeSaysTheFolderAndTheTranscriptsStay() {
        let notice = AgentAccountSignInAgain.notice(account: "ada@client.example", provider: .claudeCode)

        #expect(notice.contains("ada@client.example"))
        #expect(notice.contains("transcripts stay"))
        #expect(!notice.contains("new account"))
    }

    @Test func theRecoveryPointsAtSettingsForEveryAccountAndNoLongerAtATerminal() {
        let text = AgentAccountSignOut.recovery(provider: .codex)

        #expect(text.contains("Settings"))
        #expect(text.contains("Codex"))
        #expect(!text.contains(AgentAccountSignInAgain.actionTitle))
        #expect(!text.contains("terminal"))
        #expect(!text.contains("no sign-in button"))
    }
}

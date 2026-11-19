import Testing
import Foundation
@testable import Core

@Suite("Agent account page")
struct AgentAccountPageTests {
    private func standing(
        _ home: AgentAccountHome,
        email: String? = nil,
        report: AgentAccountLiveness.CliReport = .unanswered,
        exists: Bool = true,
        doubt: String? = nil
    ) -> AgentAccountStanding {
        AgentAccountStanding(
            home: home, identity: AgentAccountIdentity(email: email), cliReport: report,
            isolationDoubt: doubt, directoryExists: exists
        )
    }

    private func many(_ count: Int) -> [AgentAccountStanding] {
        [standing(AccountFixture.defaultClaude, email: "owner@home.example", report: .claimsSession)]
            + (1..<count).map { standing(AccountFixture.extra("extra\($0)"), email: "extra\($0)@work.example") }
    }

    private func page(
        _ standings: [AgentAccountStanding],
        for provider: AgentKind = .claudeCode,
        orphans: [AgentAccountHome] = [],
        owner: AgentAccountPanel.Owner? = nil
    ) -> AgentAccountPage {
        AgentAccountPage.make(AgentAccountPanel.make(
            provider: provider, standings: standings, orphans: orphans, codexStorageMode: .file, owner: owner
        ))
    }

    @Test(arguments: [1, 3, 6])
    func theListWithItsAddButtonComesBeforeEveryAccountsDetails(count: Int) throws {
        let made = page(many(count))

        #expect(made.sections.first == .list)
        #expect(made.sections.count == count + 1)
        #expect(made.sections.dropFirst().allSatisfy { if case .account = $0 { true } else { false } })
        #expect(made.offer.isAvailable)
    }

    @Test func theListNamesEveryAccountInTheOrderOfItsDetails() {
        let made = page(many(3))
        let detailed = made.sections.compactMap { section -> AgentAccountID? in
            if case .account(let row) = section { row.id } else { nil }
        }

        #expect(made.entries.map(\.id) == detailed)
        #expect(made.entries.map(\.title) == ["owner@home.example", "extra1@work.example", "extra2@work.example"])
    }

    @Test func anEntrySaysTheSessionOfItsAccount() {
        let made = page([
            standing(AccountFixture.defaultClaude, report: .claimsSession),
            standing(AccountFixture.work, report: .claimsNoSession),
            standing(AccountFixture.personal, exists: false),
            standing(AccountFixture.extra("shared"), report: .claimsSession, doubt: "Its login is shared."),
        ])
        let sessions = made.sections.compactMap { section -> String? in
            guard case .account(let row) = section else { return nil }
            return row.fields.first { $0.label == "Session" }?.value
        }

        #expect(made.entries.map(\.detail) == ["Signed in", "Not signed in", "Folder missing", "Signed in"])
        #expect(made.entries.map(\.detail) == sessions)
        #expect(made.entries.map(\.warns) == [false, false, true, false])
    }

    @Test func aDefaultAccountThatIsNotSetUpDoesNotWarn() throws {
        let entry = try #require(page([standing(AccountFixture.defaultClaude, exists: false)]).entries.first)

        #expect(entry.detail == "Not set up")
        #expect(!entry.warns)
    }

    @Test func anUnfinishedSignInIsListedAsOne() throws {
        let made = page([standing(AccountFixture.defaultClaude)], orphans: [AccountFixture.work])
        let entry = try #require(made.entries.last)

        #expect(entry.id == AccountFixture.work.id)
        #expect(entry.detail == "Sign-in did not finish")
        #expect(entry.warns)
    }

    @Test func theListFooterSaysWhoseAccountsTheseAreThenWhatAddingOneDoes() {
        let owner = AgentAccountPanel.Owner(
            name: "Heir", holderName: "Unified", inherits: true, refusesWithoutAccount: false,
            defaultAccount: AccountFixture.defaultClaude.id
        )

        #expect(page(many(1), owner: owner).listFooter
            == "Heir uses the accounts of Unified. Choose its own in Profile Settings. "
            + "Sign in with another Claude Code account. Each project can then choose which account runs.")
        #expect(page(many(1)).listFooter
            == "Sign in with another Claude Code account. Each project can then choose which account runs.")
    }

    @Test func anAgentThatCannotAddAnAccountHasNoListFooterAndItsReasonStaysInTheList() {
        let made = page([], for: .cursor)

        #expect(made.sections == [.list])
        #expect(made.entries.isEmpty)
        #expect(made.listFooter == nil)
        #expect(!made.offer.isAvailable)
    }

    @Test func anAgentThatCannotAddAnAccountStillSaysWhoseAccountsTheseAre() {
        let owner = AgentAccountPanel.Owner(
            name: "Heir", holderName: "Unified", inherits: true, refusesWithoutAccount: false,
            defaultAccount: nil
        )

        #expect(page([], for: .cursor, owner: owner).listFooter
            == "Heir uses the accounts of Unified. Choose its own in Profile Settings.")
    }

    @Test func theListFooterNeverRepeatsTheDefaultAccountsRole() throws {
        let owner = AgentAccountPanel.Owner(
            name: "Unified", holderName: "Unified", inherits: false, refusesWithoutAccount: false,
            defaultAccount: AccountFixture.defaultClaude.id
        )
        let made = page(many(3), owner: owner)
        let first = try #require(made.sections.dropFirst().first)
        guard case .account(let row) = first else {
            Issue.record("expected the default account's section")
            return
        }

        #expect(row.note == "The default account of Unified, used wherever a project has not chosen another.")
        #expect(made.listFooter?.contains("The default account") == false)
    }

    @Test func everySectionHasItsOwnIdentity() {
        let made = page(many(6), orphans: [AccountFixture.work])

        #expect(Set(made.sections.map(\.id)).count == made.sections.count)
    }
}

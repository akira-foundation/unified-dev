import Testing
import Foundation
@testable import Core

@Suite("Agent account line")
struct AgentAccountLineTests {
        private var standings: [AgentAccountStanding] {
        [
            AccountFixture.standing(AccountFixture.defaultClaude, email: "me@home.com"),
            AccountFixture.standing(AccountFixture.work, email: "me@client.com"),
            AccountFixture.standing(AccountFixture.personal),
            AccountFixture.standing(AccountFixture.defaultCodex),
        ]
    }

    private func line(project: AgentAccountID? = nil, provider: AgentKind = .claudeCode, standings: [AgentAccountStanding]? = nil) -> AgentAccountLine {
        let all = standings ?? self.standings
        let choice = AgentAccountChoice.resolve(provider: provider, project: project, standings: all)
        return AgentAccountLine.make(choice: choice, provider: provider, standings: all)
    }

    @Test func aProjectChoiceSaysItWasChosenForTheProject() {
        let made = line(project: AccountFixture.work.id)
        #expect(made.title == "me@client.com")
        #expect(made.sentence == "me@client.com runs here, chosen for the project.")
        #expect(!made.warns)
    }

    @Test func nothingChosenSaysTheDefaultAccountRuns() {
        let made = line()
        #expect(made.title == "me@home.com")
        #expect(made.sentence == "me@home.com runs here, the default account.")
        #expect(!made.warns)
    }

    @Test func aLostProjectChoiceRunsTheDefaultAndWarns() {
        let made = line(project: AgentAccountID("deleted"))
        #expect(made.sentence == "me@home.com runs here, the default account, because the account chosen for the project is not available for Claude Code.")
        #expect(made.warns)
    }

    @Test func aChoiceWhoseDirectoryIsGoneWarnsLikeADeletedOne() {
        let all = [AccountFixture.standing(AccountFixture.defaultClaude), AccountFixture.standing(AccountFixture.work, exists: false)]
        let made = line(project: AccountFixture.work.id, standings: all)
        #expect(made.warns)
        #expect(made.title == "Default account")
        #expect(made.sentence == "The default account runs here, because the account chosen for the project is not available for Claude Code.")
    }

    @Test func anAgentWithoutAccountsSaysItRunsWithItsOwnLoginAndShowsNoName() {
        let made = line(provider: .cursor)
        #expect(made.title == nil)
        #expect(made.sentence == "Cursor has no separate accounts, so it runs with its own login.")
        #expect(!made.warns)
    }

    @Test func grokWithNothingChosenInUnifiedSaysItRunsThisMacsLogin() {
        let made = line(provider: .grok)
        #expect(made.title == nil)
        #expect(made.sentence == "Grok has no account chosen here, so it runs with this Mac's own login.")
        #expect(!made.warns)
    }

    @Test func aLostChoiceForAnAgentWithoutAccountsStillWarns() {
        let made = line(project: AgentAccountID("deleted"), provider: .cursor)
        #expect(made.title == "Account unavailable")
        #expect(made.sentence == "Cursor has no separate accounts, so it runs with its own login. However, the account chosen for the project is not available for Cursor.")
        #expect(made.warns)
    }

    @Test func theIsolationDoubtOfAChosenAccountIsPartOfTheSentence() {
        let doubtful = AccountFixture.standing(AccountFixture.work, email: "me@client.com", doubt: "Isolation is not guaranteed.")
        let made = line(project: AccountFixture.work.id, standings: [AccountFixture.standing(AccountFixture.defaultClaude), doubtful])
        #expect(made.sentence == "me@client.com runs here, chosen for the project. Isolation is not guaranteed.")
        #expect(!made.warns)
    }

    @Test func theIsolationDoubtIsLeftOutForTheDefaultAccountBecauseItNeedsNoIsolation() {
        let doubtful = AccountFixture.standing(AccountFixture.defaultClaude, email: "me@home.com", doubt: "Isolation is not guaranteed.")
        let made = line(standings: [doubtful])
        #expect(made.sentence == "me@home.com runs here, the default account.")
    }

    @Test func theDefaultAccountChosenForTheProjectIsNamedWithItsArticle() {
        let made = line(project: AccountFixture.defaultClaude.id, standings: [AccountFixture.standing(AccountFixture.defaultClaude)])
        #expect(made.sentence == "The default account runs here, chosen for the project.")
        #expect(!made.warns)
    }

    @Test func anAccountNamedByEmailKeepsItsLowercaseInEveryReason() {
        #expect(line(project: AccountFixture.work.id).sentence.hasPrefix("me@client.com runs here"))
    }

    @Test func anAccountWhoseEmailReadsLikeTheDefaultTitleIsNotCalledTheDefaultAccount() {
        let all = [
            AccountFixture.standing(AccountFixture.defaultClaude, email: "me@home.com"),
            AccountFixture.standing(AccountFixture.work, email: "Default account"),
        ]
        let made = line(project: AccountFixture.work.id, standings: all)
        #expect(made.sentence == "Default account runs here, chosen for the project.")
    }

    @Test func theRealDefaultAccountKeepsItsArticleAndNoAppositiveWhenAnotherAccountTakesItsTitle() {
        let all = [
            AccountFixture.standing(AccountFixture.defaultClaude),
            AccountFixture.standing(AccountFixture.work, email: "Default account"),
        ]
        let made = line(standings: all)
        #expect(made.sentence == "The default account runs here.")
    }
}

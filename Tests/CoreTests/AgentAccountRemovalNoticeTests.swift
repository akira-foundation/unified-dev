import Testing
import Foundation
@testable import Core

@Suite("Where a refused account removal is told")
struct AgentAccountRemovalNoticeTests {
    private func rows(_ homes: [AgentAccountHome], orphans: [AgentAccountHome] = []) -> [AgentAccountPanel.Row] {
        AgentAccountPanel.make(
            provider: .claudeCode,
            standings: homes.map {
                AgentAccountStanding(home: $0, identity: AgentAccountIdentity(), cliReport: .unanswered, isolationDoubt: nil)
            },
            orphans: orphans, codexStorageMode: .file
        ).rows
    }

    private func row(_ home: AgentAccountHome, in rows: [AgentAccountPanel.Row]) throws -> AgentAccountPanel.Row {
        try #require(rows.first { $0.id == home.id })
    }

    @Test func aFolderInUseIsToldBesideTheAccountClickedAndNoOther() throws {
        let shown = rows([AccountFixture.defaultClaude, AccountFixture.work, AccountFixture.personal])
        let clicked = try row(AccountFixture.personal, in: shown)

        let notice = AgentAccountRemovalNotice.after(AgentAccountError.folderInUse("/f"), removing: clicked)

        #expect(shown.filter(notice.belongs).map(\.id) == [AccountFixture.personal.id])
        #expect(notice.isShown(among: shown))
        #expect(notice.message.contains("A process is still using this account's folder"))
        #expect(notice.message.hasPrefix("Could not remove \(clicked.title)"))
        #expect(!notice.forgotTheAccount)
    }

    @Test func anAccountForgottenWithItsFolderKeptIsToldBesideItsUnfinishedSignIn() throws {
        let before = rows([AccountFixture.defaultClaude, AccountFixture.work])
        let clicked = try row(AccountFixture.work, in: before)

        let notice = AgentAccountRemovalNotice.after(
            AgentAccountError.forgottenWithFolderKept("/f"), removing: clicked
        )
        let after = rows([AccountFixture.defaultClaude], orphans: [AccountFixture.work])

        #expect(notice.forgotTheAccount)
        #expect(after.filter(notice.belongs).map(\.isUnfinished) == [true])
    }

    @Test func aRemovalWhoseRowIsGoneIsNotShownAmongTheRows() throws {
        let clicked = try row(AccountFixture.work, in: rows([AccountFixture.defaultClaude, AccountFixture.work]))

        let notice = AgentAccountRemovalNotice.after(
            AgentAccountError.keychainEntriesLeft(["Claude Code-credentials-abc"]), removing: clicked
        )

        #expect(!notice.isShown(among: rows([AccountFixture.defaultClaude])))
        #expect(notice.message.hasPrefix("\(clicked.title) was removed."))
        #expect(notice.forgotTheAccount)
    }

    @Test func theSameAccountIdUnderAnotherAgentIsNotTheRowClicked() throws {
        let clicked = try row(AccountFixture.work, in: rows([AccountFixture.defaultClaude, AccountFixture.work]))
        let notice = AgentAccountRemovalNotice.after(AgentAccountError.folderInUse("/f"), removing: clicked)
        let codexWork = AgentAccountHome(
            provider: .codex, id: AccountFixture.work.id, directory: AccountFixture.work.directory, isDefault: false
        )
        let codexRows = AgentAccountPanel.make(
            provider: .codex,
            standings: [AgentAccountStanding(
                home: codexWork, identity: AgentAccountIdentity(), cliReport: .unanswered, isolationDoubt: nil
            )], codexStorageMode: .file
        ).rows

        #expect(!notice.isShown(among: codexRows))
    }

    @Test func aRemovalWhoseRowIsGoneIsShownAboveOnlyOnItsOwnAgent() throws {
        let clicked = try row(AccountFixture.work, in: rows([AccountFixture.defaultClaude, AccountFixture.work]))
        let notice = AgentAccountRemovalNotice.after(
            AgentAccountError.keychainEntriesLeft(["Claude Code-credentials-abc"]), removing: clicked
        )
        let claude = AgentAccountPanel.make(
            provider: .claudeCode, standings: [AccountFixture.standing(AccountFixture.defaultClaude)], codexStorageMode: .file
        )
        let codex = AgentAccountPanel.make(
            provider: .codex, standings: [AccountFixture.standing(AccountFixture.defaultCodex)], codexStorageMode: .file
        )

        #expect(notice.isShownAbove(claude))
        #expect(!notice.isShownAbove(codex))
    }

    @Test func aNoticeBesideItsRowIsNotAlsoShownAbove() throws {
        let panel = AgentAccountPanel.make(
            provider: .claudeCode, standings: [AccountFixture.standing(AccountFixture.work)], codexStorageMode: .file
        )
        let notice = AgentAccountRemovalNotice.after(
            AgentAccountError.folderInUse("/f"), removing: try row(AccountFixture.work, in: panel.rows)
        )

        #expect(!notice.isShownAbove(panel))
    }

    @Test func eachRefusalSaysWhatHappenedToTheAccount() throws {
        let account = try row(AccountFixture.work, in: rows([AccountFixture.work]))
        let unfinished = try row(AccountFixture.work, in: rows([], orphans: [AccountFixture.work]))

        let misplaced = AgentAccountRemovalNotice.after(AgentAccountError.folderLeftAlone("/f"), removing: account)
        let misplacedSignIn = AgentAccountRemovalNotice.after(AgentAccountError.folderLeftAlone("/f"), removing: unfinished)
        let kept = AgentAccountRemovalNotice.after(AgentAccountError.forgottenWithFolderKept("/f"), removing: account)
        let running = AgentAccountRemovalNotice.after(AgentAccountError.inUse(workspaces: ["glyphs"]), removing: account)

        #expect(misplaced.message.hasPrefix("\(account.title) was forgotten, but its folder is not where"))
        #expect(misplaced.forgotTheAccount)
        #expect(misplacedSignIn.message.hasPrefix("Could not remove \(unfinished.title): its folder is not where"))
        #expect(!misplacedSignIn.forgotTheAccount)
        #expect(kept.message.contains("may still be in use") && kept.message.contains("unfinished sign-in"))
        #expect(kept.forgotTheAccount)
        #expect(running.message.hasPrefix("Could not remove \(account.title): An agent is running under this account in glyphs"))
        #expect(!running.forgotTheAccount)
    }
}

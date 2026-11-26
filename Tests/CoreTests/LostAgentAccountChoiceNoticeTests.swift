import Testing
import Foundation
@testable import Core

@Suite("Telling the owner which projects lost the account they had chosen")
struct LostAgentAccountChoiceNoticeTests {
    private let alpha = Repo(name: "alpha", path: "/r/alpha")
    private let beta = Repo(name: "beta", path: "/r/beta")

    @Test("one project is named, with what it runs now and where to choose again")
    func oneProjectIsNamed() throws {
        let notice = try #require(LostAgentAccountChoiceNotice.notice([alpha.id], repos: [alpha, beta]))

        #expect(notice.message == "alpha runs the default account now, because the account chosen for it "
            + "no longer exists. Choose another in the project's settings.")
        #expect(notice.tone == .warning)
        #expect(notice.dismissal == .untilDismissed)
    }

    @Test("several projects are named in one sentence that agrees with them")
    func severalProjectsAreNamedTogether() throws {
        let notice = try #require(LostAgentAccountChoiceNotice.notice([alpha.id, beta.id], repos: [alpha, beta]))

        #expect(notice.message == "alpha and beta run the default account now, because the accounts chosen "
            + "for them no longer exist. Choose others in each project's settings.")
    }

    @Test("a project deleted since the loss is left out, and nothing left means no notice")
    func aDeletedProjectIsLeftOut() {
        #expect(LostAgentAccountChoiceNotice.notice([alpha.id, beta.id], repos: [beta])?.message
            .hasPrefix("beta runs") == true)
        #expect(LostAgentAccountChoiceNotice.notice([alpha.id], repos: [beta]) == nil)
        #expect(LostAgentAccountChoiceNotice.notice([], repos: [alpha]) == nil)
    }

    @Test("the notice waits for a free slot, and for the projects to be loaded before it names any")
    func theNoticeWaitsForItsMoment() throws {
        let shown = LostAgentAccountChoiceNotice.step(lost: [alpha.id], repos: [alpha], slotIsFree: true)
        guard case .show(let notice) = shown else {
            Issue.record("expected the notice to be shown, got \(shown)")
            return
        }

        #expect(notice.message.hasPrefix("alpha runs"))
        #expect(LostAgentAccountChoiceNotice.step(lost: [alpha.id], repos: [alpha], slotIsFree: false) == .hold)
        #expect(LostAgentAccountChoiceNotice.step(lost: [alpha.id], repos: [], slotIsFree: true) == .hold)
        #expect(LostAgentAccountChoiceNotice.step(lost: [], repos: [alpha], slotIsFree: true) == .hold)
    }

    @Test("a record naming only projects deleted since is forgotten without a notice")
    func aRecordOfDeletedProjectsIsForgotten() {
        #expect(LostAgentAccountChoiceNotice.step(lost: [alpha.id], repos: [beta], slotIsFree: true) == .forget)
    }

    @Test("only closing the notice counts as telling the owner, not another notice taking its place")
    func onlyClosingTheNoticeCounts() {
        let told = Notice(message: "alpha runs the default account now.")
        let other = Notice(message: "Deleted 1 archived workspace.")

        #expect(LostAgentAccountChoiceNotice.wasDismissed(told.id, before: told, after: nil))
        #expect(!LostAgentAccountChoiceNotice.wasDismissed(told.id, before: told, after: other))
        #expect(!LostAgentAccountChoiceNotice.wasDismissed(told.id, before: other, after: nil))
        #expect(!LostAgentAccountChoiceNotice.wasDismissed(nil, before: told, after: nil))
    }
}

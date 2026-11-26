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
}

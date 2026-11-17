import Foundation
import Testing
@testable import Core

@Suite("Side conversation focus")
struct SideConversationFocusTests {
    private let chatA = SessionID("a")
    private let chatB = SessionID("b")

    @Test("the inspector shows the side conversation of the chat on screen")
    func followsTheActiveChat() {
        let focus = SideConversationFocus()
        #expect(focus.parent(active: chatA, present: [chatA, chatB]) == chatA)
        #expect(focus.parent(active: chatB, present: [chatA, chatB]) == chatB)
    }

    @Test("a chat with no side conversation shows none, whatever another chat has open")
    func otherChatsStayOut() {
        let focus = SideConversationFocus()
        #expect(focus.parent(active: chatB, present: [chatA]) == nil)
    }

    @Test("a side conversation started from a pane that is not the active chat is shown until the active chat changes")
    func startedFromAnotherPane() {
        var focus = SideConversationFocus()
        focus.choose(chatB, active: chatA)
        let whileStarted = focus.parent(active: chatA, present: [chatB])
        focus.activeChatChanged()
        let afterSwitch = focus.parent(active: chatA, present: [chatB])
        #expect(whileStarted == chatB)
        #expect(afterSwitch == nil)
    }

    @Test("a chosen side conversation that ended gives way to the active chat's")
    func endedChoiceGivesWay() {
        var focus = SideConversationFocus()
        focus.choose(chatB, active: chatA)
        #expect(focus.parent(active: chatA, present: [chatA]) == chatA)
        #expect(focus.parent(active: nil, present: [chatA]) == nil)
    }
}

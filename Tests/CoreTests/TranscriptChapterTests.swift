import Foundation
import Testing
@testable import Core

@Suite("Transcript chapters")
struct TranscriptChapterTests {
    private func answer(_ text: String) -> Data {
        Data(#"{"type":"assistant","message":{"content":[{"type":"text","text":"\#(text)"}]}}"#.utf8)
    }

    private func question(_ text: String) -> Data {
        Data(#"{"type":"user","message":{"content":"\#(text)"}}"#.utf8)
    }

    @Test func aTitleIsTheFirstLineWithTextInIt() {
        #expect(TranscriptChapter.title(of: "\n  \n  Clean   the glass\nthen the wick") == "Clean the glass")
    }

    @Test func aMessageWithNoTextHasNoTitle() {
        #expect(TranscriptChapter.title(of: " \n\t\n") == nil)
    }

    @Test func aLongTitleStopsAtAWordAndSaysItWasCut() throws {
        let line = Array(repeating: "lantern", count: 20).joined(separator: " ")
        let title = try #require(TranscriptChapter.title(of: line))
        #expect(title.count <= TranscriptChapter.titleLimit)
        #expect(title.hasSuffix("lantern\u{2026}"))
    }

    @Test func aSingleWordTooLongToFitIsCutWhereTheLimitFalls() throws {
        let word = String(repeating: "w", count: TranscriptChapter.titleLimit * 2)
        let title = try #require(TranscriptChapter.title(of: word))
        #expect(title == String(repeating: "w", count: TranscriptChapter.titleLimit - 1) + "\u{2026}")
    }

    @Test func aTitleThatFitsIsKeptWhole() {
        let line = String(repeating: "a", count: TranscriptChapter.titleLimit)
        #expect(TranscriptChapter.title(of: line) == line)
    }

    @Test func anAnswerIsTitledByItsRenderedText() {
        let chapter = TranscriptChapter(seq: 4, kind: .assistantText, payload: answer("**Clean** the `glass`\\n\\nThen more."))
        #expect(chapter == TranscriptChapter(seq: 4, title: "Clean the glass"))
    }

    @Test func aQuestionIsTitledByWhatWasTyped() {
        let chapter = TranscriptChapter(seq: 1, kind: .user, payload: question("How often?"))
        #expect(chapter == TranscriptChapter(seq: 1, title: "How often?"))
    }

    @Test func anAnswerWithNoTextCannotBeAChapter() {
        #expect(TranscriptChapter(seq: 2, kind: .assistantText, payload: answer("   ")) == nil)
    }

    @Test func chaptersReadInTheOrderOfTheConversation() {
        let read = TranscriptChapter.ordered([
            TranscriptChapter(seq: 9, title: "late"), TranscriptChapter(seq: 2, title: "early"),
        ])
        #expect(read.map(\.seq) == [2, 9])
    }
}

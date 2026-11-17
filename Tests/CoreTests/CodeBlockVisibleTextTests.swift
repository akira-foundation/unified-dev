import Testing
@testable import Core

@Suite("What a code block confirmation spells out")
struct CodeBlockVisibleTextTests {
    @Test(
        "a character that hides or reorders text is spelt out",
        arguments: [
            "\u{202E}", "\u{200B}", "\u{00A0}", "\r", "\u{07}", "\u{85}", "\u{2028}", "\u{2029}",
            "\u{FE0F}", "\u{034F}", "\u{3164}", "\u{115F}", "\u{FFA0}", "\u{2800}", "\u{7F}",
        ]
    )
    func hidden(scalar: String) {
        let value = scalar.unicodeScalars.first.map { String($0.value, radix: 16, uppercase: true) } ?? ""
        #expect(CodeBlockVisibleText.shown("a\(scalar)b") == "a[U+\(value)]b")
        #expect(CodeBlockVisibleText.hiddenCount(in: "a\(scalar)b") == 1)
    }

    @Test("ordinary text, tabs, line breaks and accented letters stay as written")
    func visible() {
        let text = "echo \"café ñ € → ✓\"\tx \\\n  y"
        #expect(CodeBlockVisibleText.shown(text) == text)
        #expect(CodeBlockVisibleText.hiddenCount(in: text) == 0)
    }

    @Test("the question counts what it spelt out, in the command and the folder, so a typed look-alike is told apart")
    func countedInQuestion() {
        let typed = CodeBlockConfirmation(command: "echo [U+202E]", folder: "/w")
        let real = CodeBlockConfirmation(command: "echo \u{202E}", folder: "/w\u{200B}")
        #expect(!typed.message.contains("invisible"))
        #expect(real.message.contains("/w[U+200B]"))
        #expect(real.message.contains("It holds 2 invisible characters"))
    }

    @Test("the command that runs is the one written, not the one spelt out")
    func runsAsWritten() {
        let question = CodeBlockConfirmation(command: "echo \u{202E}x", folder: "/w")
        #expect(question.answer(confirmed: true, chatAccepts: true) == .run(command: "echo \u{202E}x", folder: "/w"))
    }
}

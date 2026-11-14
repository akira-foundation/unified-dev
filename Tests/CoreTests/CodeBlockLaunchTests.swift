import Testing
@testable import Core

@Suite("Whether a code block runs at once or asks first")
struct CodeBlockLaunchTests {
    private let folder = "/work/tree"

    @Test("a read in an orchestrator runs without asking", arguments: ["git log -1", "ls\ncat README.md"])
    func orchestratorRead(command: String) {
        #expect(CodeBlockLaunch.of(command, in: folder, orchestrates: true) == .runs)
    }

    @Test(
        "a write in an orchestrator asks, naming the command and its folder",
        arguments: ["rm -rf Sources", "echo hi > notes.txt", "git commit -am x", "git worktree add ../w feat/x"]
    )
    func orchestratorWrite(command: String) {
        #expect(
            CodeBlockLaunch.of(command, in: folder, orchestrates: true)
                == .asks(CodeBlockConfirmation(command: command, folder: folder))
        )
    }

    @Test("the question shows every line that will run and where")
    func continuationLines() {
        let command = "git worktree add \\\n  ../recovered \\\n  feat/627"
        guard case let .asks(question) = CodeBlockLaunch.of(command, in: folder, orchestrates: true) else {
            Issue.record("a write ran without asking")
            return
        }
        #expect(question.message.hasPrefix(command + "\n\n"))
        #expect(question.message.contains("It runs in \(folder)."))
        #expect(question.message.contains("may change files"))
    }

    @Test("a character that hides or reorders text is spelt out in the question, and runs as written")
    func hiddenCharacters() {
        let command = "echo safe \u{202E}fdsa\u{200B} > x\u{00A0}y\ttab"
        let question = CodeBlockConfirmation(command: command, folder: folder)
        #expect(question.message.hasPrefix("echo safe \\u{202E}fdsa\\u{200B} > x\\u{A0}y\ttab\n\n"))
        #expect(question.answer(confirmed: true) == command)
    }

    @Test("confirming runs exactly the command shown")
    func confirming() {
        let question = CodeBlockConfirmation(command: "touch a\ntouch b", folder: folder)
        #expect(question.answer(confirmed: true) == "touch a\ntouch b")
    }

    @Test("cancelling runs nothing")
    func cancelling() {
        let question = CodeBlockConfirmation(command: "rm -rf Sources", folder: folder)
        #expect(question.answer(confirmed: false) == nil)
    }

    @Test("an ordinary workspace runs whatever the reply showed", arguments: ["rm -rf Sources", "git log -1"])
    func ordinaryWorkspace(command: String) {
        #expect(CodeBlockLaunch.of(command, in: folder, orchestrates: false) == .runs)
    }
}

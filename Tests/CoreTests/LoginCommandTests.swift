import Foundation
import Testing
@testable import Core

@Suite("The login a setup fix asks for")
struct LoginCommandTests {
    @Test("a fix's command splits into the executable and its arguments")
    func splits() {
        #expect(LoginCommand(parsing: "gh auth login") == LoginCommand(executable: "gh", arguments: ["auth", "login"]))
        #expect(LoginCommand(parsing: "claude") == LoginCommand(executable: "claude"))
    }

    @Test("runs of spaces, tabs and edges add no empty arguments")
    func ignoresExtraSpace() {
        #expect(
            LoginCommand(parsing: "  codex \t login   --device-auth ")
                == LoginCommand(executable: "codex", arguments: ["login", "--device-auth"])
        )
    }

    @Test("a fix with no command, or only blanks, starts nothing")
    func nothingToRun() {
        #expect(LoginCommand(parsing: nil) == nil)
        #expect(LoginCommand(parsing: "") == nil)
        #expect(LoginCommand(parsing: "   ") == nil)
    }

    @Test("the label is the command as one line")
    func label() {
        #expect(LoginCommand(executable: "brew", arguments: ["install", "gh"]).label == "brew install gh")
    }
}

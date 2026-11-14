import Foundation
import Testing
@testable import Core

@Suite("Asking the login shell for its PATH", .tags(.subprocess), .scratchDirectory, .timeLimit(.minutes(1)))
struct LoginShellProbeTests {
    static let hasNoControllingTerminal: Bool = {
        let descriptor = open("/dev/tty", O_RDWR | O_NOCTTY)
        guard descriptor >= 0 else { return true }
        close(descriptor)
        return false
    }()

    private func directory(_ name: String) throws -> String {
        let path = TestScratch.unique(name)
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func fakeShell(_ body: String, in directory: String) throws -> String {
        let path = (directory as NSString).appendingPathComponent("shell")
        try ("#!/bin/sh\n" + body).write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    private func pids(at path: String) throws -> [pid_t] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return text.split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
    }

    @Test("a shell that answers is asked with separate flags and read")
    func readsTheAnswer() async throws {
        let folder = try directory("answering-shell")
        let shell = try fakeShell(
            """
            printf '%s' "$4" > "$(dirname "$0")/command"
            [ "$1" = -i ] && [ "$2" = -l ] && [ "$3" = -c ] || exit 3
            printf 'welcome back\\n'
            printf '\\000HOME=/x\\000PATH=/fake/bin:/usr/bin\\000'
            """,
            in: folder
        )

        let found = await LoginShellPath.discover(shell: shell, environment: [:])

        #expect(found == ["/fake/bin", "/usr/bin"])
        let asked = try String(
            contentsOfFile: (folder as NSString).appendingPathComponent("command"), encoding: .utf8
        )
        #expect(asked == LoginShellPath.sentinel)
    }

    @Test("a shell that exits non-zero answers nothing, whatever it printed")
    func failureAnswersNothing() async throws {
        let folder = try directory("failing-shell")
        let shell = try fakeShell("printf '\\000PATH=/fake/bin\\000'\nexit 1\n", in: folder)

        #expect(await LoginShellPath.discover(shell: shell, environment: [:]).isEmpty)
    }

    @Test("a shell that is not there answers nothing")
    func missingShellAnswersNothing() async {
        #expect(await LoginShellPath.discover(shell: "/nonexistent/shell", environment: [:]).isEmpty)
    }

    @Test("UD_LOGIN_SHELL_PATH=0 starts no process at all")
    func switchedOffStartsNothing() async throws {
        let folder = try directory("switched-off")
        let marker = (folder as NSString).appendingPathComponent("ran")
        let shell = try fakeShell("touch '\(marker)'\nprintf '\\000PATH=/fake/bin\\000'\n", in: folder)

        let found = await LoginShellPath.discover(shell: shell, environment: ["UD_LOGIN_SHELL_PATH": "0"])

        #expect(found.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test("a startup file that reads gets end of file rather than a wait")
    func readingStdinDoesNotWait() async throws {
        let folder = try directory("reading-shell")
        let shell = try fakeShell("read answer\nprintf '\\000PATH=/after/read\\000'\n", in: folder)
        let started = ContinuousClock.now

        let found = await LoginShellPath.discover(shell: shell, environment: [:], timeout: .seconds(5))

        #expect(found == ["/after/read"])
        #expect(started.duration(to: .now) < .seconds(4))
    }

    @Test("a startup file that never returns is stopped at the timeout, children and all")
    func hangingShellIsKilledWithItsGroup() async throws {
        let folder = try directory("hanging-shell")
        let pidsFile = (folder as NSString).appendingPathComponent("pids")
        let shell = try fakeShell(
            """
            sleep 300 &
            echo "$! $$" > "$(dirname "$0")/pids.partial"
            mv "$(dirname "$0")/pids.partial" "$(dirname "$0")/pids"
            sleep 300
            """,
            in: folder
        )

        for seconds in [1, 2, 4, 8, 16] where !FileManager.default.fileExists(atPath: pidsFile) {
            let found = await LoginShellPath.discover(shell: shell, environment: [:], timeout: .seconds(seconds))
            #expect(found.isEmpty)
        }

        let processes = try pids(at: pidsFile)
        try #require(processes.count == 2)
        await waitUntil("the shell and the child it started have both gone") {
            processes.allSatisfy { kill($0, 0) != 0 }
        }
    }

    @Test(
        "a real zsh whose .zshrc never returns is stopped at the timeout",
        .enabled(if: LoginShellProbeTests.hasNoControllingTerminal, "zsh -i contends for a controlling terminal")
    )
    func slowZshrcIsStopped() async throws {
        let home = try directory("slow-zdotdir")
        let zshrc = """
            print $$ > "$ZDOTDIR/pid.partial"
            mv "$ZDOTDIR/pid.partial" "$ZDOTDIR/pid"
            sleep 30

            """
        try zshrc.write(toFile: (home as NSString).appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)

        let pidFile = (home as NSString).appendingPathComponent("pid")

        for seconds in [2, 4, 8] where !FileManager.default.fileExists(atPath: pidFile) {
            let found = await LoginShellPath.discover(
                shell: "/bin/zsh", environment: [:], overlay: ["ZDOTDIR": home], timeout: .seconds(seconds)
            )
            #expect(found.isEmpty)
        }

        let shell = try #require(try pids(at: pidFile).first)
        await waitUntil("the zsh that was reading its .zshrc has gone") { kill(shell, 0) != 0 }
    }

    @Test(
        "a real zsh reads PATH as its .zshrc left it, even when the .zshrc asks a question",
        .enabled(if: LoginShellProbeTests.hasNoControllingTerminal, "zsh -i contends for a controlling terminal")
    )
    func interactiveZshrcAnswers() async throws {
        let home = try directory("asking-zdotdir")
        try "read -r reply\nexport PATH=/from/zshrc:$PATH\n".write(
            toFile: (home as NSString).appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8
        )

        let found = await LoginShellPath.discover(
            shell: "/bin/zsh", environment: [:], overlay: ["ZDOTDIR": home], timeout: .seconds(5)
        )

        #expect(found.first == "/from/zshrc")
    }
}

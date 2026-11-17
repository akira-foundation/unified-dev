import Foundation
import Testing
@testable import Core

private func waitForSchedulerTurns(_ turns: Int) async {
    for _ in 0..<turns {
        guard (try? await Task.sleep(for: .milliseconds(15))) != nil else { return }
    }
}

@Suite("Asking the CLI whether an account has a session")
struct AgentAccountLivenessTests {
    private let claudeHome = AgentAccountHome(
        provider: .claudeCode,
        id: AgentAccountID("work"),
        directory: URL(filePath: "/support/AgentAccounts/claudeCode/work"),
        isDefault: false
    )

    private let codexHome = AgentAccountHome(
        provider: .codex,
        id: AgentAccountID("work"),
        directory: URL(filePath: "/support/AgentAccounts/codex/work"),
        isDefault: false
    )

    private func codexLiveness(
        printing output: [String] = [],
        failing errors: [String] = [],
        status: Int32,
        environment: [String: String] = [:],
        timeout: Duration = .seconds(5),
        launches: Launches = Launches(),
        process: ScriptedStatus? = nil
    ) -> AgentAccountLiveness {
        liveness(
            printing: output, environment: environment, timeout: timeout, launches: launches,
            process: process ?? ScriptedStatus(printing: output, failing: errors, status: status)
        )
    }

    private func liveness(
        printing output: [String],
        environment: [String: String] = [:],
        timeout: Duration = .seconds(5),
        launches: Launches = Launches(),
        process: ScriptedStatus? = nil
    ) -> AgentAccountLiveness {
        AgentAccountLiveness(
            executable: "claude",
            cwd: "/scratch",
            environment: environment,
            timeout: timeout,
            makeProcess: { launch in
                launches.record(launch)
                return process ?? ScriptedStatus(printing: output)
            }
        )
    }

    @Test func aLoggedInAnswerClaimsASession() async {
        let asked = liveness(printing: [#"{"loggedIn":true,"authMethod":"claude.ai"}"#])
        let report = await asked.report(for: claudeHome)
        #expect(report == .claimsSession)
    }

    @Test func aLoggedOutAnswerClaimsNoSession() async {
        let asked = liveness(printing: [#"{"loggedIn":false,"authMethod":"none"}"#])
        let report = await asked.report(for: claudeHome)
        #expect(report == .claimsNoSession)
    }

    @Test func aPrettyPrintedAnswerSpreadOverSeveralLinesIsRead() async {
        let asked = liveness(printing: ["{", #"  "loggedIn": true,"#, #"  "apiProvider": "firstParty""#, "}"])
        let report = await asked.report(for: claudeHome)
        #expect(report == .claimsSession)
    }

    @Test func anAnswerThatIsNotJSONIsUnanswered() async {
        let asked = liveness(printing: ["Not logged in, Please run /login"])
        let report = await asked.report(for: claudeHome)
        #expect(report == .unanswered)
    }

    @Test func aProcessThatSaysNothingIsUnanswered() async {
        let asked = liveness(printing: [])
        let report = await asked.report(for: claudeHome)
        #expect(report == .unanswered)
    }

    @Test func aLoggedInThatIsNotABooleanIsUnanswered() async {
        let asked = liveness(printing: [#"{"loggedIn":"true"}"#])
        let report = await asked.report(for: claudeHome)
        #expect(report == .unanswered)
    }

    @Test func aProcessThatNeverAnswersIsGivenUpOnAndStopped() async {
        let hung = ScriptedStatus(printing: [], finishing: false)
        let asked = liveness(printing: [], timeout: .milliseconds(50), process: hung)
        let report = await asked.report(for: claudeHome)
        #expect(report == .unanswered)
        #expect(hung.terminationCount == 1)
    }

    @Test(arguments: [AgentKind.antigravity, .cursor, .openCode])
    func aProviderWithoutAStatusCommandIsNotAskedAnything(provider: AgentKind) async {
        let home = AgentAccountHome(
            provider: provider, id: AgentAccountID("work"),
            directory: URL(filePath: "/support/AgentAccounts/\(provider.rawValue)/work"), isDefault: false
        )
        let launches = Launches()
        let asked = liveness(printing: [#"{"loggedIn":true}"#], launches: launches)
        let report = await asked.report(for: home)
        #expect(report == .unanswered)
        #expect(launches.all.isEmpty)
        #expect(!AgentAccountLiveness.canAsk(about: provider))
    }

    @Test func theCommandIsAimedAtTheAccountDirectoryAndInheritsNoIdentity() async throws {
        let launches = Launches()
        let inherited = [
            "PATH": "/usr/bin",
            "ANTHROPIC_API_KEY": "made-up-key",
            "CLAUDE_CODE_USER_EMAIL": "owner@example.com",
            "CLAUDE_CONFIG_DIR": "/the/hosts/own",
        ]
        let asked = liveness(printing: [#"{"loggedIn":true}"#], environment: inherited, launches: launches)

        _ = await asked.report(for: claudeHome)

        let launch = try #require(launches.all.first)
        #expect(launches.all.count == 1)
        #expect(launch.arguments == ["auth", "status"])
        #expect(launch.environment["CLAUDE_CONFIG_DIR"] == claudeHome.directory.path)
        #expect(launch.environment["ANTHROPIC_API_KEY"] == nil)
        #expect(launch.environment["CLAUDE_CODE_USER_EMAIL"] == nil)
        #expect(launch.environment["PATH"] == "/usr/bin")
    }

    @Test func codexExitingZeroWithAChatGPTLoginClaimsASession() async {
        let asked = codexLiveness(failing: ["Logged in using ChatGPT"], status: 0)
        let report = await asked.report(for: codexHome)
        #expect(report == .claimsSession)
    }

    @Test func codexExitingZeroWithAnApiKeyLoginClaimsASessionWhateverTheText() async {
        let asked = codexLiveness(failing: ["Logged in using API key"], status: 0)
        let report = await asked.report(for: codexHome)
        #expect(report == .claimsSession)
    }

    @Test func codexExitingZeroWithAnUnexpectedTextStillClaimsASession() async {
        let asked = codexLiveness(failing: ["Signed in as someone, wording changed"], status: 0)
        let report = await asked.report(for: codexHome)
        #expect(report == .claimsSession)
    }

    @Test func codexSayingNotLoggedInWithAFailureStatusClaimsNoSession() async {
        let asked = codexLiveness(failing: ["Not logged in"], status: 1)
        let report = await asked.report(for: codexHome)
        #expect(report == .claimsNoSession)
    }

    @Test func codexNotLoggedInOnStandardOutputIsReadToo() async {
        let asked = codexLiveness(printing: ["Not logged in"], status: 1)
        let report = await asked.report(for: codexHome)
        #expect(report == .claimsNoSession)
    }

    @Test func codexFailingWithUnexpectedTextIsUnansweredAndNeverNoSession() async {
        let asked = codexLiveness(failing: ["error: unexpected argument 'status'"], status: 1)
        let report = await asked.report(for: codexHome)
        #expect(report == .unanswered)
        #expect(report != .claimsNoSession)
    }

    @Test func codexFailingWithNoOutputAtAllIsUnansweredAndNeverNoSession() async {
        let asked = codexLiveness(status: 127)
        let report = await asked.report(for: codexHome)
        #expect(report == .unanswered)
        #expect(report != .claimsNoSession)
    }

    @Test func codexThatNeverAnswersIsGivenUpOnAndStopped() async {
        let hung = ScriptedStatus(printing: [], status: 0, finishing: false)
        let asked = codexLiveness(status: 0, timeout: .milliseconds(50), process: hung)
        let report = await asked.report(for: codexHome)
        #expect(report == .unanswered)
        #expect(hung.terminationCount == 1)
    }

    @Test func codexWhoseExitStatusNeverArrivesUntilItIsTerminatedIsStillGivenUpOn() async {
        let hung = ScriptedStatus(printing: [], status: 0, finishing: false, exitWaitsForTermination: true)
        let asked = codexLiveness(status: 0, timeout: .milliseconds(50), process: hung)

        let report = await withTaskGroup(of: AgentAccountLiveness.CliReport?.self) { group in
            group.addTask { await asked.report(for: codexHome) }
            group.addTask {
                await waitForSchedulerTurns(200)
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            hung.terminate()
            return first.flatMap { $0 }
        }

        #expect(report == .unanswered)
    }

    @Test func theCodexCommandIsAimedAtTheAccountDirectoryAndInheritsNoIdentity() async throws {
        let launches = Launches()
        let inherited = [
            "PATH": "/usr/bin",
            "OPENAI_API_KEY": "made-up-key",
            "ANTHROPIC_API_KEY": "made-up-key",
            "CODEX_HOME": "/the/hosts/own",
        ]
        let asked = codexLiveness(failing: ["Logged in using ChatGPT"], status: 0, environment: inherited, launches: launches)

        _ = await asked.report(for: codexHome)

        let launch = try #require(launches.all.first)
        #expect(launches.all.count == 1)
        #expect(launch.executable == "codex")
        #expect(launch.arguments == ["login", "status"])
        #expect(launch.environment["CODEX_HOME"] == codexHome.directory.path)
        #expect(launch.environment["OPENAI_API_KEY"] == nil)
        #expect(launch.environment["ANTHROPIC_API_KEY"] == nil)
        #expect(launch.environment["PATH"] == "/usr/bin")
    }

    @Test func eachAgentIsAskedWithTheExecutableTheOwnerConfiguredForIt() async {
        let launches = Launches()
        let asked = AgentAccountLiveness.using(
            executables: [.claudeCode: "/opt/claude/bin/claude", .codex: "/opt/codex/bin/codex"],
            makeProcess: { launch in
                launches.record(launch)
                return ScriptedStatus(printing: [#"{"loggedIn":true}"#])
            }
        )

        _ = await asked.report(for: claudeHome)
        _ = await asked.report(for: codexHome)

        #expect(launches.all.map(\.executable) == ["/opt/claude/bin/claude", "/opt/codex/bin/codex"])
    }

    @Test func anAgentWithNoConfiguredExecutableIsAskedWithItsBareName() async {
        let launches = Launches()
        let asked = AgentAccountLiveness.using(
            executables: [:],
            makeProcess: { launch in
                launches.record(launch)
                return ScriptedStatus(printing: [#"{"loggedIn":true}"#])
            }
        )

        _ = await asked.report(for: claudeHome)
        _ = await asked.report(for: codexHome)

        #expect(launches.all.map(\.executable) == [AgentRunner.executable, CodexClient.executable])
    }
}

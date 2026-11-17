import Foundation
import Testing
@testable import Core

@Suite("What the alias probe lets out of this Mac, and what it leaves behind", .tags(.agentProtocol, .subprocess), .scratchDirectory, .timeLimit(.minutes(2)))
struct ClaudeAliasProbeIsolationTests {
    private func fakeCLI(_ body: String) throws -> String {
        let path = TestScratch.path("bin/claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
        )
        try ("#!/bin/sh\n" + body + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    private func realProbe(_ executable: String, inherited: [String: String] = [:]) -> ClaudeAliasProbe {
        ClaudeAliasProbe(
            executable: executable, workRoot: probeWorkRoot(),
            environment: ["PATH": "/usr/bin:/bin"].merging(inherited) { _, new in new },
            timeout: .seconds(30), exitGrace: .milliseconds(500), managed: unmanaged(),
            activity: ClaudeAccountActivity()
        )
    }

    private func resolve(
        _ probe: ClaudeAliasProbe, _ aliases: [String], account: AgentAccountHome, upTo deadline: Duration
    ) async -> ClaudeAliasAnswers? {
        let finished = AwaitedAnswer<ClaudeAliasAnswers>()
        Task { finished.set(await probe.resolve(aliases, account: account)) }
        return await finished.wait(upTo: deadline)
    }

    @Test("a CLI that ignores the request to stop is killed, and the probe still answers")
    func killsACLIThatIgnoresTerminate() async {
        let launches = ProbeLaunches()
        let probe = scriptedProbe(launches, ignoresTerminate: true) { alias in [probeInitLine("claude-\(alias)-5-5")] }

        let answers = await resolve(probe, ["opus", "sonnet"], account: probeAccount(), upTo: .seconds(10))

        #expect(answers?.probed == ["opus": "claude-opus-5-5", "sonnet": "claude-sonnet-5-5"])
        #expect(launches.processes.map(\.killCount) == [1, 1])
        #expect(launches.processes.allSatisfy { !$0.isRunning })
    }

    @Test("a process that ignores SIGTERM is ended by SIGKILL instead of holding the probe")
    func endsARealProcessThatIgnoresSigterm() async throws {
        let record = TestScratch.path("record")
        try FileManager.default.createDirectory(atPath: record, withIntermediateDirectories: true)
        let cli = try fakeCLI("""
        trap '' TERM
        echo $$ > "$PROBE_RECORD/pid"
        echo '{"type":"system","subtype":"init","model":"claude-opus-5-5"}'
        exec /bin/sleep 600
        """)

        let answers = await resolve(
            realProbe(cli, inherited: ["PROBE_RECORD": record]), ["opus"], account: probeAccount(), upTo: .seconds(15)
        )
        let pid = try #require(Int32(String(contentsOfFile: record + "/pid", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        let stillAlive = kill(pid, 0) == 0
        if stillAlive { kill(pid, SIGKILL) }

        #expect(answers?.probed == ["opus": "claude-opus-5-5"])
        #expect(!stillAlive)
    }

    @Test("the address the CLI is given gets no answer and every proxy it is given refuses, while the CLI runs")
    func nothingTheCLISendsGetsAnAnswer() async throws {
        let record = TestScratch.path("record")
        try FileManager.default.createDirectory(atPath: record, withIntermediateDirectories: true)
        let cli = try fakeCLI("""
        printf '%s\\0' "$@" > "$PROBE_RECORD/args"
        env > "$PROBE_RECORD/env.partial" && mv "$PROBE_RECORD/env.partial" "$PROBE_RECORD/env"
        while [ ! -e "$PROBE_RECORD/go" ]; do /bin/sleep 0.05; done
        echo '{"type":"system","subtype":"init","model":"claude-opus-5-5"}'
        exec /bin/sleep 30
        """)
        let inherited = [
            "PROBE_RECORD": record,
            "ANTHROPIC_BASE_URL": "https://api.anthropic.com",
            "HTTPS_PROXY": "http://proxy.example:8080",
        ]

        let answers = AwaitedAnswer<ClaudeAliasAnswers>()
        let probe = realProbe(cli, inherited: inherited)
        Task { answers.set(await probe.resolve(["opus"], account: probeAccount())) }
        await waitUntil("the CLI wrote what it was given") { FileManager.default.fileExists(atPath: record + "/env") }
        let environment = try String(contentsOfFile: record + "/env", encoding: .utf8)
            .split(separator: "\n")
            .reduce(into: [String: String]()) { found, line in
                guard let equals = line.firstIndex(of: "=") else { return }
                found[String(line[..<equals])] = String(line[line.index(after: equals)...])
            }
        let arguments = try String(contentsOfFile: record + "/args", encoding: .utf8).split(separator: "\0").map(String.init)
        let settingsAt = try #require(arguments.firstIndex(of: "--settings"))
        let settings = try JSONDecoder().decode(SettingsEnvironment.self, from: Data(arguments[settingsAt + 1].utf8)).env
        let named = ["ANTHROPIC_BASE_URL"] + Self.proxyNames
        let base = try #require(environment["ANTHROPIC_BASE_URL"].flatMap(LoopbackExchange.port(of:)))
        let proxies = Self.proxyNames.map { environment[$0].flatMap(LoopbackExchange.port(of:)) }
        let modelRequest = LoopbackExchange.send(
            "POST /v1/messages HTTP/1.1\r\nHost: api.anthropic.com\r\n\r\n", to: base, waiting: .seconds(2)
        )
        let proxied = await LoopbackExchange.sendAtOnce(
            "CONNECT api.anthropic.com:443 HTTP/1.1\r\n\r\n", to: proxies.compactMap(\.self), waiting: .seconds(15)
        )
        try "".write(toFile: record + "/go", atomically: true, encoding: .utf8)
        let resolved = await answers.wait(upTo: .seconds(20))

        #expect(resolved?.probed == ["opus": "claude-opus-5-5"])
        #expect(modelRequest?.isStillWaiting == true, "\(String(describing: modelRequest))")
        #expect(proxies.allSatisfy { $0 != nil && $0 != base })
        #expect(proxied.count == Self.proxyNames.count)
        #expect(proxied.allSatisfy { $0?.wasClosedUnanswered == true }, "\(proxied)")
        #expect(named.allSatisfy { settings[$0] != nil && settings[$0] == environment[$0] })
    }

    private static let proxyNames = ["ALL_PROXY", "HTTPS_PROXY", "HTTP_PROXY", "all_proxy", "http_proxy", "https_proxy"]

    private struct SettingsEnvironment: Decodable {
        let env: [String: String]
    }

    @Test("each probe runs in a directory of its own, found empty and removed afterwards")
    func runsInAFreshDirectory() async throws {
        let record = TestScratch.path("record")
        try FileManager.default.createDirectory(atPath: record, withIntermediateDirectories: true)
        let cli = try fakeCLI("""
        pwd -P >> "$PROBE_RECORD/cwd"
        ls -A | wc -l | tr -d ' ' >> "$PROBE_RECORD/entries"
        touch left-behind
        echo '{"type":"system","subtype":"init","model":"claude-opus-5-5"}'
        """)
        let probe = realProbe(cli, inherited: ["PROBE_RECORD": record])

        _ = await resolve(probe, ["opus"], account: probeAccount(), upTo: .seconds(15))
        _ = await resolve(probe, ["opus"], account: probeAccount(), upTo: .seconds(15))
        let directories = try String(contentsOfFile: record + "/cwd", encoding: .utf8).split(separator: "\n").map(String.init)
        let entries = try String(contentsOfFile: record + "/entries", encoding: .utf8).split(separator: "\n")

        #expect(directories.count == 2)
        #expect(Set(directories).count == 2)
        #expect(entries == ["0", "0"])
        #expect(!directories.contains { $0.contains(AgentScratchDirectory.folderName) })
        #expect(directories.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    }
}

@Suite("When the alias probe stays out of the way", .tags(.agentProtocol), .scratchDirectory)
struct ClaudeAliasProbeRestraintTests {
    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("a managed settings source that sets anything stops the probe before any launch", arguments: [
        "root/managed-settings.json", "root/managed-settings.d/10-proxy.json",
        "preferences/tester/com.anthropic.claudecode.plist", "preferences/com.anthropic.claudecode.plist",
        "account/remote-settings.json",
    ])
    func managedSettingsStopTheProbe(document: String) async throws {
        let account = probeAccount()
        let managed = unmanaged()
        let url = document.hasPrefix("account/")
            ? account.directory.appending(path: String(document.dropFirst("account/".count)))
            : URL(filePath: TestScratch.path("managed/\(document)"))
        let contents = url.pathExtension == "plist"
            ? #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>apiKeyHelper</key><string>x</string></dict></plist>"#
            : #"{"env":{"ANTHROPIC_BASE_URL":"https://gateway.example"}}"#
        try write(contents, to: url)
        let launches = ProbeLaunches()

        let answers = await scriptedProbe(launches, managed: managed) { alias in [probeInitLine("claude-\(alias)-5-5")] }
            .resolve(["opus"], account: account)

        #expect(launches.launches.isEmpty)
        #expect(answers.all.isEmpty)
    }

    @Test("an empty managed document, as a personal account carries, does not stop it")
    func emptyRemoteSettingsLetTheProbeRun() async throws {
        let account = probeAccount()
        try write("{}", to: account.directory.appending(path: "remote-settings.json"))
        let launches = ProbeLaunches()

        let answers = await scriptedProbe(launches) { alias in [probeInitLine("claude-\(alias)-5-5")] }
            .resolve(["opus"], account: account)

        #expect(answers.probed == ["opus": "claude-opus-5-5"])
    }

    @Test("a managed document that cannot be read is treated as one that sets something")
    func unreadableManagedSettingsStopTheProbe() async throws {
        try write("not json", to: URL(filePath: TestScratch.path("managed/root/managed-settings.json")))
        let launches = ProbeLaunches()

        _ = await scriptedProbe(launches) { _ in [] }.resolve(["opus"], account: probeAccount())

        #expect(launches.launches.isEmpty)
    }

    @Test("an alias the account pins in its settings is answered from the pin, without a launch")
    func pinnedAliasesAreReadNotProbed() async throws {
        let account = probeAccount()
        try write(
            #"{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"claude-opus-4-1-20250805","ANTHROPIC_BASE_URL":"https://x"}}"#,
            to: account.directory.appending(path: "settings.json")
        )
        let launches = ProbeLaunches()

        let answers = await scriptedProbe(launches) { alias in [probeInitLine("claude-\(alias)-5-5")] }
            .resolve(["opus", "sonnet"], account: account)

        #expect(answers.pinned == ["opus": "claude-opus-4-1-20250805"])
        #expect(answers.probed == ["sonnet": "claude-sonnet-5-5"])
        #expect(launches.launches.map(probedAlias(of:)) == ["sonnet"])
    }

    @Test("no launch starts while a turn of the same account is running, and another account is not held")
    func waitsForTheAccountsTurns() async {
        let activity = ClaudeAccountActivity()
        let work = probeAccount("work")
        let client = probeAccount("client")
        let lease = await activity.beginRun(work.id)
        let launches = ProbeLaunches()
        let probe = scriptedProbe(launches, activity: activity) { alias in [probeInitLine("claude-\(alias)-5-5")] }

        let held = await probe.resolve(["opus"], account: work)
        let free = await probe.resolve(["opus"], account: client)
        lease?.end()
        let afterwards = await probe.resolve(["opus"], account: work)

        #expect(held.all.isEmpty)
        #expect(free.probed == ["opus": "claude-opus-5-5"])
        #expect(afterwards.probed == ["opus": "claude-opus-5-5"])
        #expect(launches.launches.count == 2)
    }

    @Test("a turn that starts during a probe waits for the launch in flight, and the probe asks nothing more", .timeLimit(.minutes(1)))
    func aTurnWaitsForTheLaunchInFlight() async throws {
        let activity = ClaudeAccountActivity()
        let work = probeAccount()
        let launches = ProbeLaunches()
        let probe = scriptedProbe(launches, timeout: .seconds(30), activity: activity) { _ in [] }

        let answers = AwaitedAnswer<ClaudeAliasAnswers>()
        Task { answers.set(await probe.resolve(["opus", "sonnet"], account: work)) }
        await waitUntil("the probe launched") { !launches.launches.isEmpty }
        let admitted = AwaitedAnswer<ClaudeRunLease>()
        Task { if let lease = await activity.beginRun(work.id) { admitted.set(lease) } }
        await waitUntil("the turn waits for the launch") { activity.waitingRuns(work.id) == 1 }
        let admittedDuringLaunch = admitted.answer != nil
        launches.processes.first?.terminate()
        let lease = await admitted.wait(upTo: .seconds(5))
        let finished = await answers.wait(upTo: .seconds(5))
        lease?.end()

        #expect(lease != nil)
        #expect(finished != nil)
        #expect(!admittedDuringLaunch)
        #expect(launches.launches.count == 1)
    }

    @Test("the directory the CLI will use is the one checked, including one the app inherited")
    func readsTheDirectoryTheCLIWillUse() async throws {
        let inheritedDirectory = URL(filePath: TestScratch.path("inherited-config"), directoryHint: .isDirectory)
        try write(#"{"env":{"HTTPS_PROXY":"http://gateway.example"}}"#, to: inheritedDirectory.appending(path: "remote-settings.json"))
        let launches = ProbeLaunches()
        let probe = ClaudeAliasProbe(
            executable: "claude", workRoot: probeWorkRoot(), environment: ["CLAUDE_CONFIG_DIR": inheritedDirectory.path],
            managed: unmanaged(), activity: ClaudeAccountActivity(),
            makeProcess: { launch in
                let process = ScriptedProbe(printing: [probeInitLine("claude-opus-5-5")])
                launches.record(launch, process)
                return process
            }
        )

        let answers = await probe.resolve(["opus"], account: nil)

        #expect(launches.launches.isEmpty)
        #expect(answers.all.isEmpty)
    }

    @Test("a drop-in directory that cannot be listed is treated as one that sets something")
    func unlistableDropInsStopTheProbe() throws {
        let dropIns = URL(filePath: TestScratch.path("managed/root/managed-settings.d"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dropIns, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dropIns.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dropIns.path) }

        #expect(unmanaged().governs(accountDirectory: probeAccount().directory))
    }

    @Test("an empty managed profile, and drop-ins that are not JSON, do not stop the probe")
    func emptyProfilesAndOtherFilesDoNotCount() throws {
        try write(
            #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>"#,
            to: URL(filePath: TestScratch.path("managed/preferences/com.anthropic.claudecode.plist"))
        )
        try write("anything", to: URL(filePath: TestScratch.path("managed/root/managed-settings.d/README")))

        #expect(!unmanaged().governs(accountDirectory: probeAccount().directory))
    }

    @Test("a pin that is empty or not text is no pin, and a pin is trimmed", arguments: [
        (#""   ""#, nil as String?), ("42", nil), (#"" claude-opus-4-1 ""#, "claude-opus-4-1"),
    ])
    func pinsAreReadStrictly(value: String, pinned: String?) throws {
        let settings = URL(filePath: TestScratch.path("pins/settings.json"))
        try write(#"{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":\#(value)}}"#, to: settings)

        #expect(ClaudeAliasPins.pinned(["opus"], inSettingsAt: settings)["opus"] == pinned)
    }

    @Test("when every alias is pinned nothing is launched")
    func everyAliasPinnedLaunchesNothing() async throws {
        let account = probeAccount()
        try write(
            #"{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"claude-opus-4-1","ANTHROPIC_DEFAULT_SONNET_MODEL":"claude-sonnet-4-5"}}"#,
            to: account.directory.appending(path: "settings.json")
        )
        let launches = ProbeLaunches()

        let answers = await scriptedProbe(launches) { _ in [] }.resolve(["opus", "sonnet"], account: account)

        #expect(launches.launches.isEmpty)
        #expect(answers.pinned.count == 2)
    }

    @Test("every turn waiting on a probe is admitted when it ends, and the account stays held until each one leaves")
    func admitsEveryWaitingTurn() async throws {
        let activity = ClaudeAccountActivity()
        let account = AgentAccountID("work")
        #expect(activity.beginProbe(account))
        let first = AwaitedAnswer<ClaudeRunLease>()
        let second = AwaitedAnswer<ClaudeRunLease>()
        Task { if let lease = await activity.beginRun(account) { first.set(lease) } }
        Task { if let lease = await activity.beginRun(account) { second.set(lease) } }
        await waitUntil("both turns wait for the probe") { activity.waitingRuns(account) == 2 }

        activity.endProbe(account)
        let leases = [await first.wait(upTo: .seconds(5)), await second.wait(upTo: .seconds(5))].compactMap(\.self)
        leases[0].end()
        let heldByTheSecond = !activity.beginProbe(account)
        leases[1].end()
        leases[1].end()

        #expect(leases.count == 2)
        #expect(heldByTheSecond)
        #expect(activity.beginProbe(account))
    }

    @Test("a turn waiting on a probe gives its place back when its task is cancelled, and the probe is not ended")
    func aCancelledWaitLeaves() async {
        let activity = ClaudeAccountActivity()
        let account = AgentAccountID("work")
        #expect(activity.beginProbe(account))
        let answered = AwaitedAnswer<Bool>()
        let waiting = Task {
            let lease = await activity.beginRun(account)
            answered.set(lease != nil)
        }
        await waitUntil("the turn waits for the probe") { activity.waitingRuns(account) == 1 }

        waiting.cancel()
        let admitted = await answered.wait(upTo: .seconds(5))
        let heldAfterwards = activity.isRunning(account)
        let probeStillHeld = !activity.beginProbe(account)
        activity.endProbe(account)

        #expect(admitted == false)
        #expect(!heldAfterwards)
        #expect(probeStillHeld)
    }

    @Test("a ticket withdrawn before it is presented is never admitted, and one withdrawn after admission keeps its lease")
    func aWithdrawnTicketIsRefused() async {
        let activity = ClaudeAccountActivity()
        let account = AgentAccountID("work")
        let early = ClaudeRunTicket()
        activity.withdraw(early)
        let late = ClaudeRunTicket()

        let refused = await activity.beginRun(account, ticket: early)
        let lease = await activity.beginRun(account, ticket: late)
        activity.withdraw(late)
        let heldAfterLateWithdrawal = activity.isRunning(account)
        lease?.end()

        #expect(refused == nil)
        #expect(lease != nil)
        #expect(heldAfterLateWithdrawal)
        #expect(!activity.isRunning(account))
    }

    @Test("a lease dropped without being ended still frees its account")
    func aDroppedLeaseFreesTheAccount() async {
        let activity = ClaudeAccountActivity()
        let account = AgentAccountID("work")
        do {
            _ = await activity.beginRun(account)
        }

        #expect(!activity.isRunning(account))
    }
}

import Foundation
import Testing
@testable import Core

private typealias Spawn = @Sendable (AgentLaunch) -> any AgentProcessing

private func spawnsAfterTheProbe(_ start: @escaping @Sendable (@escaping Spawn) async -> Void) async -> [Bool] {
    let watch = ProbeWatch()
    watch.install()
    defer { LoginShellPath.forget() }
    let box = ProcessBox()

    LoginShellPath.begin()
    let running = Task {
        await start { launch in
            watch.noteSpawn()
            return box.factory(launch)
        }
    }
    await waitUntil("the CLI was spawned") { !watch.spawns.isEmpty }
    running.cancel()
    for process in box.processes { process.terminate() }
    return watch.spawns
}

private func quotaAskPath(_ make: (@escaping Spawn) -> any AgentQuotaSource) async -> (path: String?, adopted: String) {
    let adopted = "/nonexistent/login-shell-\(UUID().uuidString)"
    let current = Shell.environment()["PATH"]?.components(separatedBy: ":") ?? []
    LoginShellPath.install {
        try? await Task.sleep(for: .milliseconds(400))
        return current + [adopted]
    }
    defer { LoginShellPath.forget() }
    let box = ProcessBox()
    let source = make(box.factory)

    LoginShellPath.begin()
    let asking = Task { _ = await source.read() }
    await waitUntil("the quota was asked") { !box.processes.isEmpty }
    asking.cancel()
    for process in box.processes { process.terminate() }
    return (box.processes.first?.launch.environment["PATH"], adopted)
}

private func executableTheProbeInstalls() -> String {
    let path = TestScratch.unique("login-shell-cli")
    LoginShellPath.install {
        try? await Task.sleep(for: .milliseconds(400))
        FileManager.default.createFile(
            atPath: path, contents: Data("#!/bin/sh\necho 1.0.0\n".utf8), attributes: [.posixPermissions: 0o755]
        )
        return []
    }
    return path
}

extension LoginShellAdoptionTests {
    @Test("an agent CLI only the login shell can see is detected on the first look")
    func detectionWaitsForTheProbe() async {
        let executable = executableTheProbeInstalls()
        defer { LoginShellPath.forget() }

        LoginShellPath.begin()
        let status = await AgentCatalog(overrides: [.grok: executable]).status(for: .grok)

        #expect(status.connection != .notInstalled)
    }

    @Test("the installed agent list waits for the login shell before it looks")
    func installedKindsWaitForTheProbe() async {
        let executable = executableTheProbeInstalls()
        defer { LoginShellPath.forget() }

        LoginShellPath.begin()
        let installed = await AgentCatalog.installedKinds(overrides: [.grok: executable])

        #expect(installed.contains(.grok))
    }

    @Test("the Codex model catalogue is not fetched until the login shell has answered")
    func codexModelsWaitForTheProbe() async {
        let spawns = await spawnsAfterTheProbe { spawn in
            _ = try? await CodexModelCatalog.live(cwd: "/tmp/w", makeProcess: spawn).models()
        }

        #expect(spawns == [true])
    }

    @Test("the Codex skill catalogue is not fetched until the login shell has answered")
    func codexSkillsWaitForTheProbe() async {
        let spawns = await spawnsAfterTheProbe { spawn in
            _ = await CodexSkillCatalog.live(project: "/tmp/w", makeProcess: spawn).skills()
        }

        #expect(spawns == [true])
    }

    @Test("the Codex speed is not read until the login shell has answered")
    func codexSpeedWaitsForTheProbe() async {
        let spawns = await spawnsAfterTheProbe { spawn in
            _ = try? await CodexSpeed.read(cwd: "/tmp/w", modelID: "gpt-5.6-sol", makeProcess: spawn)
        }

        #expect(spawns == [true])
    }

    @Test("the Grok model catalogue is not fetched until the login shell has answered")
    func grokModelsWaitForTheProbe() async {
        let spawns = await spawnsAfterTheProbe { spawn in
            let catalog = GrokModelCatalog.live(cwd: "/tmp/w", makeClient: { configuration in
                ACPClient(configuration: configuration, makeProcess: spawn)
            })
            _ = try? await catalog.models()
        }

        #expect(spawns == [true])
    }

    @Test("a Claude Code quota source made before the probe answers asks with the adopted PATH")
    func claudeQuotaAsksWithTheAdoptedPath() async {
        let asked = await quotaAskPath { spawn in ClaudeCodeQuotaSource(accountPath: "/nonexistent/claude.json", makeProcess: spawn) }

        #expect(asked.path?.components(separatedBy: ":").contains(asked.adopted) == true)
    }

    @Test("a Codex quota source made before the probe answers asks with the adopted PATH")
    func codexQuotaAsksWithTheAdoptedPath() async {
        let asked = await quotaAskPath { spawn in CodexQuotaSource(makeProcess: spawn) }

        #expect(asked.path?.components(separatedBy: ":").contains(asked.adopted) == true)
    }

    @Test("a Grok quota source made before the probe answers asks with the adopted PATH")
    func grokQuotaAsksWithTheAdoptedPath() async {
        let asked = await quotaAskPath { spawn in GrokQuotaSource(makeProcess: spawn) }

        #expect(asked.path?.components(separatedBy: ":").contains(asked.adopted) == true)
    }
}

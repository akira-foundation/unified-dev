#if DEBUG
import AppKit
import Foundation
import Core

@MainActor
enum BusyProbe {
    private static let harness = ProbeHarness(subject: "busy")

    static var isRequested: Bool { harness.isRequested && (try? PreviewLaunch.root()) != nil }

    private static var busyCount: Int { ProbeHarness.count("--busy-workspaces", or: 5) }
    private static var seconds: Int { ProbeHarness.count("--busy-seconds", or: 60) }
    private static var writeEvery: Int { ProbeHarness.count("--busy-write-every", or: 2) }
    private static var quietSelection: Bool { ProbeHarness.isPresent("--busy-quiet-selected") }
    private static var subagentCount: Int { ProbeHarness.count("--busy-subagents", or: 0) }

    static func schedule() {
        Task { @MainActor in await run() }
    }

    private static func run() async {
        guard let app = await loadedApp() else { harness.fail("the workspaces never loaded") }
        let busy = Array(app.workspaces.filter { FileManager.default.fileExists(atPath: $0.path) }.prefix(busyCount))
        guard busy.count == busyCount else {
            harness.fail("wanted \(busyCount) workspaces on disk and found \(busy.count)")
        }
        let quiet = app.workspaces.first { workspace in
            !busy.contains { $0.id == workspace.id } && FileManager.default.fileExists(atPath: workspace.path)
        }
        if quietSelection, quiet == nil { harness.fail("wanted a quiet workspace on disk beside the busy ones") }
        let selected = quietSelection ? quiet : busy.first
        if let selected { app.selection = .workspace(selected.id) }

        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                await app.runDiffRefreshTick(activity: .foreground)
                if quietSelection { await app.selectedModel?.refreshChanges(.quiet) }
                try? await Task.sleep(for: .seconds(DiffRefreshSchedule.tick))
            }
        }
        let writer = Task.detached {
            var round = 0
            while !Task.isCancelled {
                round += 1
                for workspace in busy { touch(workspace.path, round: round) }
                try? await Task.sleep(for: .seconds(writeEvery))
            }
        }

        try? await Task.sleep(for: .seconds(12))
        let progress = startSubagents(in: app)
        if progress != nil { try? await Task.sleep(for: .seconds(2)) }
        let spawnsBefore = Shell.spawnCount
        let tallyBefore = ActivityTally.read()
        let mainBefore = ProbeHarness.mainThreadCPUSeconds()
        let processBefore = ProcessCPU.read()

        try? await Task.sleep(for: .seconds(seconds))

        let spawns = Shell.spawnCount - spawnsBefore
        let tally = ActivityTally.read() - tallyBefore
        let mainCPU = ProbeHarness.mainThreadCPUSeconds() - mainBefore
        let processCPU = ProcessCPU.read() - processBefore
        writer.cancel()
        ticker.cancel()
        progress?.cancel()

        let busyIDs = Set(busy.map(\.id))
        let shownAdditions = app.workspaces.filter { busyIDs.contains($0.id) }.map(\.additions).reduce(0, +)
        let minutes = Double(seconds) / 60
        let ticks = Double(seconds) / DiffRefreshSchedule.tick
        let report: [String: JSONValue] = [
            "busyWorkspaces": .integer(busy.count),
            "busyAdditionsShown": .integer(shownAdditions),
            "workspaces": .integer(app.workspaces.count),
            "seconds": .integer(seconds),
            "spawns": .integer(spawns),
            "spawnsPerTick": .number(Double(spawns) / ticks),
            "reloads": .integer(tally.reloads),
            "reloadsPerMinute": .number(Double(tally.reloads) / minutes),
            "inboxReloads": .integer(tally.inboxReloads),
            "changeReads": .integer(tally.changeReads),
            "changeGenerations": .integer(tally.changeGenerations),
            "quietSelection": .bool(quietSelection),
            "subagentsStarted": .integer(subagentCount),
            "subagentRowsShown": .integer(app.selection.workspaceID.map { app.subagents(of: $0).count } ?? 0),
            "subagentRowWrites": .integer(tally.subagentRowWrites),
            "sidebarReflows": .integer(tally.sidebarReflows),
            "sidebarRowWrites": .integer(tally.sidebarRowWrites),
            "inboxReloadsPerMinute": .number(Double(tally.inboxReloads) / minutes),
            "mainThreadCpuMs": .number(mainCPU * 1000),
            "mainThreadCpuMsPerMinute": .number(mainCPU * 1000 / minutes),
            "processCpuMs": .number(processCPU.own * 1000),
            "childCpuMs": .number(processCPU.children * 1000),
        ]
        harness.write(
            .object(report.merging(harness.conditions(window: nil)) { mine, _ in mine }), echo: true
        )
        exit(0)
    }

    private static func startSubagents(in app: AppModel) -> Task<Void, Never>? {
        guard subagentCount > 0 else { return nil }
        guard let transcript = app.selectedModel?.activeTranscript else {
            harness.fail("the selected workspace has no open chat to run subagents in")
        }
        for index in 0..<subagentCount {
            transcript.probeApply(.started(SubagentStart(
                id: SubagentID("probe-\(index)"), toolUseID: "toolu_probe_\(index)",
                description: "Probe subagent \(index)", type: "general-purpose"
            )))
        }
        return Task { @MainActor in
            var reported = 30
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                reported += 2
                for index in 0..<subagentCount {
                    transcript.probeApply(.progressed(SubagentProgress(
                        parentToolUseID: "toolu_probe_\(index)", elapsedSeconds: reported
                    )))
                }
            }
        }
    }

    private static func loadedApp() async -> AppModel? {
        for _ in 0..<240 {
            if let app = AppModel.probeInstance, app.isLoaded,
               app.workspaces.count >= busyCount {
                try? await Task.sleep(for: .seconds(3))
                return app
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    private nonisolated static func touch(_ path: String, round: Int) {
        let file = URL(fileURLWithPath: path).appendingPathComponent("busy-probe.txt")
        let lines = (0...round).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try? Data(lines.utf8).write(to: file)
    }
}
#endif

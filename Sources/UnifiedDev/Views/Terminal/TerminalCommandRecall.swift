import Foundation
import Observation
import Core

@MainActor
@Observable
final class TerminalCommandRecall {
    struct Pane: Sendable {
        let pane: String
        let shell: Int32
        let session: String?
    }

    private var offers: [String: String] = [:]

    private var sent: [String: String] = [:]

    private var recorded: [String: String] = [:]

    private var busy: Set<String> = []
    private(set) var runningCommands: Set<String> = []
    private var resumeCommands: [String: String] = [:]

    func remember(_ command: String, sentTo pane: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy.contains(pane) else { return }
        sent[pane] = trimmed
    }

    func rememberResume(_ command: String, inPane pane: String, store: Store) async {
        resumeCommands[pane] = command
        guard sent[pane] != command else { return }
        sent[pane] = command
        recorded[pane] = command
        if offers[pane] != nil { offers[pane] = command }
        try? await store.setSetting(TerminalCommandMemory.key(paneID: pane), command)
    }

    func offers(inPanes panes: [String]) -> [String: String] {
        offers.filter { panes.contains($0.key) }
    }

    func accepted(_ command: String, inPane pane: String) {
        if offers.removeValue(forKey: pane) != nil { sent[pane] = command }
    }

    func withdraw(inPane pane: String) {
        withdrawn.insert(pane)
        if offers[pane] != nil { offers[pane] = nil }
    }

    @ObservationIgnored private var withdrawn: Set<String> = []

    func dismiss(inPane pane: String, store: Store?) {
        offers[pane] = nil
        forget(panes: [pane], store: store)
    }

    func forget(panes: [String], store: Store?) {
        for pane in panes {
            offers[pane] = nil
            sent[pane] = nil
            recorded[pane] = nil
            resumeCommands[pane] = nil
            busy.remove(pane)
            runningCommands.remove(pane)
            withdrawn.remove(pane)
        }
        guard let store, !panes.isEmpty else { return }
        Task {
            for pane in panes {
                try? await store.setSetting(TerminalCommandMemory.key(paneID: pane), nil)
            }
        }
    }

    func considerOffer(
        inPane pane: String,
        session: String?,
        persistence: TerminalPersistence?,
        store: Store?
    ) async {
        guard let store, offers[pane] == nil else { return }
        let stored = try? await store.setting(TerminalCommandMemory.key(paneID: pane))
        let isAgent = CenterTabStore.shared.tabsByWorkspace.values.joined().contains {
            $0.id == pane && $0.agentSessionID != nil
        }
        guard let command = TerminalCommandMemory.offerable(
            stored, maximumLength: isAgent ? 262_144 : TerminalCommandMemory.lengthLimit
        ) else { return }
        if isAgent { resumeCommands[pane] = command }
        recorded[pane] = command

        if let session, let persistence {
            let pids = await persistence.panePIDs(notOlderThan: .zero)
            if let shell = pids[session], let table = await ProcessTable.recent(notOlderThan: .zero),
               table.foregroundCommand(ofShell: shell) != nil {
                return
            }
        }
        guard !withdrawn.contains(pane) else { return }
        offers[pane] = command
    }

    func record(panes: [Pane], persistence: TerminalPersistence?, store: Store) async {
        runningCommands.formIntersection(panes.map(\.pane))
        guard !panes.isEmpty,
              let table = await ProcessTable.recent(notOlderThan: TerminalActivitySchedule.readingMaxAge) else { return }

        var pids: [String: Int32] = [:]
        if panes.contains(where: { $0.session != nil }) {
            pids = await persistence?.panePIDs(notOlderThan: TerminalActivitySchedule.readingMaxAge) ?? [:]
        }

        for pane in panes {
            let shell = pane.session.flatMap { pids[$0] } ?? pane.shell
            let running = table.foregroundCommand(ofShell: shell)
            if running == nil || table.interactiveAgent(ofShell: shell) != nil {
                runningCommands.remove(pane.pane)
            } else {
                runningCommands.insert(pane.pane)
            }
            if running == nil {
                busy.remove(pane.pane)
                sent[pane.pane] = nil
                guard offers[pane.pane] == nil else { continue }
                resumeCommands[pane.pane] = nil
            } else {
                busy.insert(pane.pane)
            }
            let resume = table.interactiveAgent(ofShell: shell) == nil ? nil : resumeCommands[pane.pane]
            let remembered = resume ?? TerminalCommandMemory.remembered(
                sent: sent[pane.pane], running: running
            )
            guard remembered != recorded[pane.pane] else { continue }
            try? await store.setSetting(TerminalCommandMemory.key(paneID: pane.pane), remembered)
            recorded[pane.pane] = remembered
        }
    }
}

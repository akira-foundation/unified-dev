import AppKit
import SwiftUI
import QuartzCore
import Core

@MainActor
enum StreamProbe {
    private static let harness = ProbeHarness(subject: "stream")

    static var isRequested: Bool { harness.isRequested }

    private static var workspaceID: WorkspaceID? {
        ProbeHarness.value(for: "--stream-workspace").map(WorkspaceID.init)
    }

    private static var typed: Int { ProbeHarness.count("--stream-typed", or: 120) }
    private static var deltas: Int { ProbeHarness.count("--stream-deltas", or: 200) }
    private static var chunk: Int { ProbeHarness.count("--stream-chunk", or: 14) }
    private static var rate: Int { max(1, ProbeHarness.count("--stream-rate", or: 25)) }

    static func schedule() {
        Task { @MainActor in await run() }
    }

    static func attach(_ model: AppModel) {
        guard isRequested else { return }
        ProbeHarness.attach(model)
    }

    private static func run() async {
        let (window, contentView) = await harness.window()

        guard let workspaceID else { harness.fail("--stream-workspace names no workspace") }
        OpenWorkspaceNotification.post(workspaceID)
        try? await Task.sleep(for: .seconds(8))

        guard let app = ProbeHarness.appModel else { harness.fail("no app model") }
        guard let model = app.existingModel(for: workspaceID) else {
            harness.fail("workspace \(workspaceID.rawValue) is not open")
        }
        guard let session = model.activeSession,
              let transcript = model.existingTranscript(for: session.id) else {
            harness.fail("workspace \(workspaceID.rawValue) has no conversation open")
        }
        guard let editor = composer(in: contentView) else {
            harness.fail("no composer text view found")
        }

        let recorder = FrameRecorder(view: contentView) { CGFloat(transcript.rows.count) }

        harness.markStarted()

        if StreamToolResultsProbe.isRequested, let store = app.store {
            let tools = await StreamToolResultsProbe.measure(transcript: transcript, store: store)
            harness.write(.object([
                "workspace": .string(workspaceID.rawValue),
                "tools": .object(tools),
            ].merging(harness.conditions(window: window)) { mine, _ in mine }))
            exit(0)
        }

        if StreamMarkdownProbe.isRequested {
            let markdown = await StreamMarkdownProbe.measure(
                transcript: transcript, recorder: recorder, chunk: chunk, rate: rate
            )
            harness.write(.object([
                "workspace": .string(workspaceID.rawValue),
                "markdown": .object(markdown),
            ].merging(harness.conditions(window: window)) { mine, _ in mine }))
            exit(0)
        }

        let typing = await measureTyping(editor: editor, transcript: transcript, recorder: recorder)
        let streaming = await measureStreaming(transcript: transcript, recorder: recorder)

        harness.write(.object([
            "workspace": .string(workspaceID.rawValue),
            "workspaceName": .string(model.workspace.name),
            "sessionRows": .integer(transcript.rows.count),
            "typing": .object(typing),
            "streaming": .object(streaming),
        ].merging(harness.conditions(window: window)) { mine, _ in mine }))
        exit(0)
    }

    private static func measureTyping(
        editor: ComposerTextView, transcript: TranscriptModel, recorder: FrameRecorder
    ) async -> [String: JSONValue] {
        editor.window?.makeFirstResponder(editor)
        let sentence = Array("the quick brown fox jumps over the lazy dog. ")
        var typedCharacters = 0

        recorder.start()
        let cpuBefore = ProbeHarness.mainThreadCPUSeconds()
        let wallBefore = CACurrentMediaTime()
        for index in 0..<typed {
            editor.insertText(String(sentence[index % sentence.count]), replacementRange: NSRange(location: NSNotFound, length: 0))
            typedCharacters += 1
            try? await Task.sleep(for: .milliseconds(8))
        }
        let wall = CACurrentMediaTime() - wallBefore
        let cpu = ProbeHarness.mainThreadCPUSeconds() - cpuBefore
        recorder.stop()

        transcript.draft = ""

        var report = ProbeHarness.frameTimings(recorder.intervals.map { $0 * 1000 })
        report["characters"] = .integer(typedCharacters)
        report["wallSeconds"] = .number(wall)
        report["mainThreadCpuMsPerKeystroke"] = .number(
            typedCharacters > 0 ? cpu * 1000 / Double(typedCharacters) : 0
        )
        report["didType"] = .bool(typedCharacters > 0)
        return report
    }

    private static func measureStreaming(
        transcript: TranscriptModel, recorder: FrameRecorder
    ) async -> [String: JSONValue] {
        let text = String(repeating: "x", count: max(1, chunk))
        let gap = Duration.milliseconds(1000 / rate)

        recorder.start()
        let cpuBefore = ProbeHarness.mainThreadCPUSeconds()
        let wallBefore = CACurrentMediaTime()
        for _ in 0..<deltas {
            await transcript.acceptForProbe(.streamDelta(.text(text + " ")))
            try? await Task.sleep(for: gap)
        }
        let wall = CACurrentMediaTime() - wallBefore
        let cpu = ProbeHarness.mainThreadCPUSeconds() - cpuBefore
        recorder.stop()

        var report = ProbeHarness.frameTimings(recorder.intervals.map { $0 * 1000 })
        report["deltas"] = .integer(deltas)
        report["chunkCharacters"] = .integer(chunk)
        report["ratePerSecond"] = .integer(rate)
        report["wallSeconds"] = .number(wall)
        report["mainThreadCpuMsPerDelta"] = .number(
            deltas > 0 ? cpu * 1000 / Double(deltas) : 0
        )
        report["tailCharacters"] = .integer(transcript.streamingText.count)
        return report
    }

    private static func composer(in root: NSView) -> ComposerTextView? {
        if let editor = root as? ComposerTextView { return editor }
        for subview in root.subviews {
            if let found = composer(in: subview) { return found }
        }
        return nil
    }
}

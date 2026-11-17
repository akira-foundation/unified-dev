import QuartzCore
import Core

@MainActor
enum StreamMarkdownProbe {
    static var isRequested: Bool { ProbeHarness.isPresent("--stream-markdown") }

    private static var characters: Int { ProbeHarness.count("--stream-markdown-characters", or: 20_000) }

    static func reply(characters: Int) -> String {
        var text = "# A reply that arrives in pieces\n\nIt carries every block the transcript draws.\n\n"
        var section = 0
        while text.count < characters {
            section += 1
            text += """
            ## Step \(section)

            The parser reads this paragraph, which wraps across **several** words and a `span` of code.

            ```swift
            let step = \(section)

            print("step \\(step)")
            ```

            - the first point of step \(section)
            - the second point

              with a second paragraph

            - the third point

            | Name | Size | Kind |
            | :--- | ---: | :--: |
            | alpha | \(section) | file |
            | beta | \(section * 2) | folder |

            > a quoted line closes step \(section)


            """
        }
        return text
    }

    static func measure(
        transcript: TranscriptModel, recorder: FrameRecorder, chunk: Int, rate: Int
    ) async -> [String: JSONValue] {
        let text = reply(characters: characters)
        var drawn: (text: String, blocks: [MarkdownBlock])?
        var parseSeconds = 0.0
        var parses = 0
        MarkdownStreamSlot.probeTap = { text, blocks, seconds in
            drawn = (text, blocks)
            parseSeconds += seconds
            parses += 1
        }
        let gap = Duration.milliseconds(1000 / max(1, rate))
        var deltas = 0
        var cursor = text.startIndex

        recorder.start()
        let cpuBefore = ProbeHarness.mainThreadCPUSeconds()
        let wallBefore = CACurrentMediaTime()
        while cursor < text.endIndex {
            let end = text.index(cursor, offsetBy: max(1, chunk), limitedBy: text.endIndex) ?? text.endIndex
            await transcript.acceptForProbe(.streamDelta(.text(String(text[cursor..<end]))))
            cursor = end
            deltas += 1
            try? await Task.sleep(for: gap)
        }
        try? await Task.sleep(for: .milliseconds(500))
        let wall = CACurrentMediaTime() - wallBefore
        let cpu = ProbeHarness.mainThreadCPUSeconds() - cpuBefore
        recorder.stop()
        MarkdownStreamSlot.probeTap = nil

        let finished = MarkdownParser.parse(text)
        var report = ProbeHarness.frameTimings(recorder.intervals.map { $0 * 1000 })
        report["characters"] = .integer(text.count)
        report["deltas"] = .integer(deltas)
        report["chunkCharacters"] = .integer(chunk)
        report["ratePerSecond"] = .integer(rate)
        report["wallSeconds"] = .number(wall)
        report["mainThreadCpuSeconds"] = .number(cpu)
        report["mainThreadCpuMsPerDelta"] = .number(deltas > 0 ? cpu * 1000 / Double(deltas) : 0)
        report["parses"] = .integer(parses)
        report["parseMs"] = .number(parseSeconds * 1000)
        report["parseMsPerFlush"] = .number(parses > 0 ? parseSeconds * 1000 / Double(parses) : 0)
        report["drawnCharacters"] = .integer(drawn?.text.count ?? 0)
        report["finishedBlocks"] = .integer(finished.count)
        report["codeBlocks"] = .integer(finished.filter(isCode).count)
        report["lists"] = .integer(finished.filter(isList).count)
        report["tables"] = .integer(finished.filter(isTable).count)
        report["streamedMatchesFinished"] = .bool(drawn?.text == text && drawn?.blocks == finished)
        return report
    }

    private static func isCode(_ block: MarkdownBlock) -> Bool {
        if case .codeBlock = block { return true }
        return false
    }

    private static func isList(_ block: MarkdownBlock) -> Bool {
        if case .bulletList = block { return true }
        return false
    }

    private static func isTable(_ block: MarkdownBlock) -> Bool {
        if case .table = block { return true }
        return false
    }
}

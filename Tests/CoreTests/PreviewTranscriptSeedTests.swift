import Testing
import Foundation
@testable import Core

private func scenario(_ transcripts: [PreviewScenario.Transcript]) -> PreviewScenario {
    PreviewScenario(
        projects: [PreviewScenario.Project(name: "billing")],
        transcripts: transcripts
    )
}

private func seeder() throws -> PreviewScenarioSeeder {
    PreviewScenarioSeeder(
        manager: WorkspaceManager(store: try makeTestStore("preview-transcripts")),
        scratchRoot: TestScratch.unique("preview-scratch")
    )
}

@Suite("Preview transcript seeding")
struct PreviewTranscriptSeedTests {
    @Test("a scenario that names transcripts with no home to write into is refused")
    func withoutAnOverrideNothingIsWritten() throws {
        let made = try seeder()
        #expect(throws: PreviewScenarioError.noTranscriptHome) {
            try made.seedTranscripts(scenario([.init()]), at: Date(), home: nil)
        }
    }

    @Test("a scenario with no transcripts needs no home")
    func noTranscriptsNeedsNoHome() throws {
        #expect(try seeder().seedTranscripts(scenario([]), at: Date(), home: nil) == 0)
    }

    @Test("a seeded transcript reads back as the turns it names")
    func seededTranscriptIsRead() throws {
        let home = URL(filePath: TestScratch.unique("transcript-home"), directoryHint: .isDirectory)
        let made = try seeder()
        let written = try made.seedTranscripts(
            scenario([.init(project: "billing", model: "claude-opus-5", daysAgo: 0, turns: 5)]),
            at: Date(),
            home: home
        )
        #expect(written == 1)

        let source = TranscriptSources.sources(provider: home)[0]
        let files = TranscriptSources.files(in: source)
        #expect(files.count == 1)
        let result = try TranscriptReader.read(try #require(files.first), from: 0, carry: TranscriptCarry())
        #expect(result.records.count == 5)
        #expect(result.records.allSatisfy { $0.model == "claude-opus-5" })
        #expect(result.records.allSatisfy { $0.directory == made.projectsRoot + "/billing" })
    }

    @Test("a Codex transcript carries the model from its turn context")
    func seededCodexTranscript() throws {
        let home = URL(filePath: TestScratch.unique("transcript-home"), directoryHint: .isDirectory)
        let made = try seeder()
        _ = try made.seedTranscripts(
            scenario([.init(provider: .codex, project: "billing", model: "gpt-6-sol", turns: 3)]),
            at: Date(),
            home: home
        )
        let source = TranscriptSources.sources(provider: home)[1]
        let file = try #require(TranscriptSources.files(in: source).first)
        let result = try TranscriptReader.read(file, from: 0, carry: TranscriptCarry())
        #expect(result.records.count == 3)
        #expect(result.records.allSatisfy { $0.model == "gpt-6-sol" })
    }

    @Test("a transcript cut inside its last number loses that turn and nothing else")
    func truncatedTranscript() throws {
        let home = URL(filePath: TestScratch.unique("transcript-home"), directoryHint: .isDirectory)
        _ = try seeder().seedTranscripts(
            scenario([.init(project: "billing", turns: 6, truncated: true)]), at: Date(), home: home
        )
        let source = TranscriptSources.sources(provider: home)[0]
        let file = try #require(TranscriptSources.files(in: source).first)
        let text = try String(decoding: Data(contentsOf: file.url), as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 6)

        let result = try TranscriptReader.read(file, from: 0, carry: TranscriptCarry())
        #expect(result.records.count == 5)
        #expect(result.offset < file.size)

        var carry = TranscriptCarry()
        let tail = String(text.suffix(from: text.index(text.startIndex, offsetBy: result.offset)))
        #expect(UsageLine.record(inLine: tail, provider: .claudeCode, carry: &carry) == nil)
    }

    @Test("padding makes one transcript bigger than another with the same turns")
    func paddingChangesSize() throws {
        let home = URL(filePath: TestScratch.unique("transcript-home"), directoryHint: .isDirectory)
        _ = try seeder().seedTranscripts(
            scenario([
                .init(project: "billing", turns: 4),
                .init(project: "billing", turns: 4, padding: 2_000),
            ]),
            at: Date(),
            home: home
        )
        let source = TranscriptSources.sources(provider: home)[0]
        let sizes = TranscriptSources.files(in: source).map(\.size).sorted()
        #expect(sizes.count == 2)
        #expect(sizes[1] > sizes[0] * 2)
    }

    @Test("a rollout transcript is named by the session inside its file name")
    func rolloutSessionName() {
        let name = "rollout-2026-10-11T11-00-00-0199a-7a22-a753-be11-87e74249.jsonl"
        #expect(TranscriptSources.agentSessionID(ofFile: "/t/" + name) == "0199a-7a22-a753-be11-87e74249")
        #expect(TranscriptSources.agentSessionID(ofFile: "/t/abc.jsonl") == "abc")
    }

    @Test("a file that is not a transcript of that provider is not read")
    func onlyTranscriptsAreRead() throws {
        let home = URL(filePath: TestScratch.unique("transcript-home"), directoryHint: .isDirectory)
        _ = try seeder().seedTranscripts(
            scenario([.init(provider: .codex, project: "billing")]), at: Date(), home: home
        )
        let sessions = home.appending(path: ".codex/sessions")
        try Data("{}".utf8).write(to: sessions.appending(path: "notes.jsonl"))
        try Data("{}".utf8).write(to: sessions.appending(path: "rollout-stray.txt"))

        let source = TranscriptSources.sources(provider: home)[1]
        let names = TranscriptSources.files(in: source).map { $0.url.lastPathComponent }
        #expect(names.count == 1)
        #expect(names.allSatisfy { $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl") })
    }

    @Test("a scenario seeded through the seeder reports what it wrote")
    func seedReportsTranscripts() async throws {
        let home = URL(filePath: TestScratch.unique("transcript-home"), directoryHint: .isDirectory)
        let made = try seeder()
        let written = try made.seedTranscripts(
            scenario([.init(project: "billing"), .init(provider: .codex, project: "billing")]),
            at: Date(),
            home: home
        )
        #expect(written == 2)
        let claude = TranscriptSources.sources(provider: home)[0]
        let codex = TranscriptSources.sources(provider: home)[1]
        #expect(TranscriptSources.files(in: claude).count == 1)
        #expect(TranscriptSources.files(in: codex).count == 1)
    }

    @Test("a transcript written with nothing named takes the defaults")
    func decoderDefaults() throws {
        let decoded = try JSONDecoder().decode(
            PreviewScenario.Transcript.self, from: Data("{}".utf8)
        )
        #expect(decoded.provider == .claudeCode)
        #expect(decoded.model == "claude-opus-5")
        #expect(decoded.turns == 20)
        #expect(decoded.padding == 0)
        #expect(decoded.daysAgo == 0)
        #expect(!decoded.truncated)
    }

    @Test("a transcript naming a project the scenario never creates is refused")
    func unknownProjectIsRefused() {
        let made = scenario([.init(project: "nowhere")])
        #expect(made.problems.contains { $0.contains("nowhere") })
    }

    @Test("a transcript with no turns is refused")
    func emptyTranscriptIsRefused() {
        #expect(scenario([.init(turns: 0)]).problems.contains { $0.contains("turns") })
    }

    @Test("a provider that keeps no usage on disk cannot be given a transcript")
    func providerWithoutTranscriptsIsRefused() {
        let made = scenario([.init(provider: .grok, project: "billing")])
        #expect(made.problems.contains { $0.contains(AgentKind.grok.label) })
    }

    @Test("seeding again clears what the last scenario left behind")
    func seedingClearsStaleTranscripts() throws {
        let home = URL(filePath: TestScratch.unique("transcript-home"), directoryHint: .isDirectory)
        let made = try seeder()
        _ = try made.seedTranscripts(
            scenario([.init(project: "billing"), .init(project: "billing")]), at: Date(), home: home
        )
        _ = try made.seedTranscripts(scenario([.init(project: "billing")]), at: Date(), home: home)
        let source = TranscriptSources.sources(provider: home)[0]
        #expect(TranscriptSources.files(in: source).count == 1)
    }
}

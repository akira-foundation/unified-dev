import Foundation
import Testing
@testable import Core

@Suite("The scenario the profile agent accounts walkthrough uses")
struct PreviewProfileAgentAccountsFileTests {
    @Test func itGivesAProfileGrokAccountsOfItsOwnBesideClaudeCodeAndCodex() throws {
        let root = URL(fileURLWithPath: #filePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let read = try PreviewScenario.read(path: root + "/Tools/scenarios/profile-agent-accounts.json")
        let akiras = read.accounts.filter { $0.profile == "Akira" }

        #expect(read.problems.isEmpty)
        #expect(Set(akiras.map(\.provider)) == [.claudeCode, .codex, .grok])
        #expect(akiras.contains { $0.provider == .grok && $0.isProfileDefault })
        #expect(read.projects.first?.accounts == ["grok": "night"])
    }
}

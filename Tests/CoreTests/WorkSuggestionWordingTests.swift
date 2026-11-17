import Foundation
import Testing
@testable import Core

@Suite("What a card says when it cannot start")
struct WorkSuggestionWordingTests {
    @Test("a workspace at its ceiling is told the ceiling it has and that archiving brings it back under")
    func ceiling() {
        let text = WorkSuggestionWording.sentence(
            for: .overAllowance("agent sentence", retry: .whenAWorkspaceIsArchived(limit: 16))
        )

        #expect(text.contains("16 workspaces"))
        #expect(text.contains("not archived"))
        #expect(text.contains("below 16"))
        #expect(!text.localizedCaseInsensitiveContains("running"))
    }

    @Test("the owner's rate names the time a start is free again")
    func rate() {
        let at = Date(timeIntervalSince1970: 1_800_000_300)

        let text = WorkSuggestionWording.sentence(for: .overAllowance("agent sentence", retry: .after(at)))

        #expect(text.contains(at.formatted(date: .omitted, time: .shortened)))
        #expect(text.contains("15 minutes"))
    }

    @Test("a full crew is told to wait for one to stop")
    func fullCrew() {
        let text = WorkSuggestionWording.sentence(for: CrewLaunchRefusal.rule(.tooMany(running: Crew.ceiling)))

        #expect(text.contains("when one of them stops"))
    }

    @Test("a failure is passed on as it was written")
    func failures() {
        #expect(WorkSuggestionWording.sentence(for: LaunchRefusal.failed("git said no")) == "git said no")
        #expect(WorkSuggestionWording.sentence(for: CrewLaunchRefusal.refused("No worktree.")) == "No worktree.")
    }

    @Test("a press after the agent withdrew it reads as the agent's doing")
    func withdrawn() {
        #expect(WorkSuggestionWording.taken(.withdrawn) == "Withdrawn by the agent")
        #expect(WorkSuggestionWording.taken(.startedWorkspace(WorkspaceID("w"), name: "Last row")).contains("Last row"))
    }
}

import Testing
@testable import Core

@Suite("What the start project card is showing")
struct StartProjectStageTests {
    private let creationFailed = NewProjectFailure(
        title: "Could not start the project",
        message: "git init said no.",
        folderWasCreated: true
    )

    private let cloneFailed = CloneFailure(
        message: "Repository not found.",
        folderWasCreated: false
    )

    @Test("only the landing takes the whole card, so the form is drawn under the plinth")
    func onlyTheLandingTakesTheCard() {
        #expect(StartProjectStage.landing.takesTheWholeCard)
        #expect(!StartProjectStage.naming.takesTheWholeCard)
        #expect(!StartProjectStage.cloning.takesTheWholeCard)
        #expect(!StartProjectStage.creating(.initialise).takesTheWholeCard)
        #expect(!StartProjectStage.fetching.takesTheWholeCard)
    }

    @Test("a failure never takes the whole card, because the footer is the only way out of it")
    func aFailureLeavesRoomForTheFooter() {
        #expect(!StartProjectStage.after(cloneFailed).takesTheWholeCard)
        #expect(!StartProjectStage.after(creationFailed).takesTheWholeCard)
    }

    @Test("leaving discards while work is running, so a half made folder is never kept")
    func discardsWhileRunning() {
        #expect(StartProjectStage.creating(.initialise).discardsOnLeaving)
        #expect(StartProjectStage.fetching.discardsOnLeaving)
        #expect(!StartProjectStage.naming.discardsOnLeaving)
        #expect(!StartProjectStage.cloning.discardsOnLeaving)
        #expect(!StartProjectStage.landing.discardsOnLeaving)
    }

    @Test("a failure that left a folder behind discards on leaving, so closing the card cleans up")
    func aFailureThatLeftAFolderDiscards() {
        #expect(StartProjectStage.after(creationFailed).discardsOnLeaving)
        #expect(!StartProjectStage.after(cloneFailed).discardsOnLeaving)
    }

    @Test("cancelling the form or the clone goes back to the landing rather than closing the card")
    func cancelGoesBackToTheLanding() {
        #expect(StartProjectStage.naming.leaving == .landing)
        #expect(StartProjectStage.cloning.leaving == .landing)
    }

    @Test("the landing has nowhere to go back to, and running work is stopped rather than left")
    func nowhereToGoBackTo() {
        #expect(StartProjectStage.landing.leaving == nil)
        #expect(StartProjectStage.creating(.push).leaving == nil)
        #expect(StartProjectStage.fetching.leaving == nil)
    }

    @Test("trying again after a failure returns to the half the owner was in")
    func tryingAgainReturnsToTheRightHalf() {
        #expect(StartProjectStage.after(creationFailed).leaving == .naming)
        #expect(StartProjectStage.after(cloneFailed).leaving == .cloning)
    }

    @Test("a failure carries its own title, and whether a folder is left to remove")
    func failureCarriesItsFacts() {
        guard case .failed(let fault) = StartProjectStage.after(creationFailed) else {
            return #expect(Bool(false), "a failure should read as failed")
        }

        #expect(fault.title == "Could not start the project")
        #expect(fault.message == "git init said no.")
        #expect(fault.folderWasCreated)
        #expect(fault.half == .naming)
    }

    @Test("a clone failure says it was a clone, and reports no folder to remove")
    func cloneFailureCarriesItsFacts() {
        guard case .failed(let fault) = StartProjectStage.after(cloneFailed) else {
            return #expect(Bool(false), "a failure should read as failed")
        }

        #expect(fault.title == "Could not clone the repository")
        #expect(fault.half == .cloning)
        #expect(!fault.folderWasCreated)
    }

    @Test("each stage names itself, and no two stages share a name")
    func everyStageNamesItself() {
        let stages: [StartProjectStage] = [
            .landing, .naming, .cloning, .creating(.initialise), .fetching,
            .after(cloneFailed),
        ]
        let titles = stages.map(\.title)

        #expect(titles == [
            "Start a project",
            "New project",
            "Clone a repository",
            "Setting it up",
            "Cloning",
            "Could not clone the repository",
        ])
        #expect(Set(titles).count == titles.count)
    }

    @Test("a failed clone keeps its advice, git's whole output and the host it offers to trust")
    func cloneFailureKeepsWhatTheSheetShows() {
        let offer = KnownHostOffer(host: "ssh.bitbucket.org", lines: ["ssh.bitbucket.org ssh-ed25519 AAAA"], fingerprints: ["ED25519 SHA256:x"])
        let failure = CloneFailure(
            message: "Host key verification failed.", folderWasCreated: false,
            advice: "Compare the fingerprint.", detail: "Cloning into 'x'...\nHost key verification failed.", hostOffer: offer
        )

        guard case .failed(let fault) = StartProjectStage.after(failure) else {
            Issue.record("a clone failure did not become a failed stage")
            return
        }

        #expect(fault.message == "Host key verification failed.")
        #expect(fault.advice == "Compare the fingerprint.")
        #expect(fault.detail == "Cloning into 'x'...\nHost key verification failed.")
        #expect(fault.hostOffer == offer)
        #expect(fault.half == .cloning)
    }
}

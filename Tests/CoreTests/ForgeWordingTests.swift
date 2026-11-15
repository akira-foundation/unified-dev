import Foundation
import Testing
@testable import Core

@Suite("What the checks tab says about Bitbucket")
struct ForgeWordingTests {
    @Test("the checks tab names the CLI of the host it reads from")
    func checks() {
        let bitbucket = ChecksWording(forge: .bitbucket)
        let gitHub = ChecksWording(forge: .gitHub)

        #expect(bitbucket.cannotAskTitle(access: .notInstalled) == "The Bitbucket CLI is not installed")
        #expect(bitbucket.cannotAskMessage(access: .signedOut).contains("bkt"))
        #expect(bitbucket.cannotAskAction(access: .signedOut) == nil)
        #expect(bitbucket.summary(access: .signedOut) == "Bitbucket not connected")
        #expect(bitbucket.loading == "Asking Bitbucket")
        #expect(gitHub.cannotAskTitle(access: .notInstalled) == "The GitHub CLI is not installed")
        #expect(gitHub.cannotAskAction(access: .signedOut) == "Connect GitHub")
        #expect(gitHub.none == "GitHub has not reported a check run for this branch.")
    }
}

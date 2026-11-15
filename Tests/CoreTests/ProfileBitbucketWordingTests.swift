import Foundation
import Testing
@testable import Core

@Suite("What a profile's settings say about its Bitbucket sign-in")
struct ProfileBitbucketWordingTests {
    @Test("a profile's Bitbucket footnote says whose sign-in it uses")
    func profileFootnote() {
        let account = BitbucketAccount(user: "kid", method: "oauth")

        #expect(ProfileBitbucketWording.footnote(
            source: .inherits, isInitial: true, profileName: "Unified", account: account, installed: true
        ) == "Unified uses this Mac's bkt sign-in, signed in as kid.")
        #expect(ProfileBitbucketWording.footnote(
            source: .own, isInitial: false, profileName: "Debtges", account: nil, installed: true
        ).contains("never uses this Mac's"))
        #expect(ProfileBitbucketWording.footnote(
            source: .own, isInitial: false, profileName: "Debtges", account: account, installed: true
        ) == "Pull requests, builds and agents in Debtges's Bitbucket projects run as kid.")
        #expect(ProfileBitbucketWording.footnote(
            source: .own, isInitial: false, profileName: "Debtges", account: nil, installed: false
        ).contains("brew install bitbucket-cli"))
    }
}

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

    @Test("an action on a Bitbucket pull request that bkt cannot reach says where to sign in, or what to install")
    func cannotReach() {
        #expect(ProfileBitbucketWording.cannotReachTitle(.notInstalled) == "The Bitbucket CLI is not installed")
        #expect(ProfileBitbucketWording.cannotReachMessage(.notInstalled).contains("brew install bitbucket-cli"))
        #expect(ProfileBitbucketWording.cannotReachTitle(.signedOut) == "Bitbucket is not connected")
        #expect(ProfileBitbucketWording.cannotReachMessage(.signedOut).contains("from the profile's settings"))
        #expect(ChecksWording(forge: .bitbucket).cannotAskMessage(access: .signedOut).hasSuffix(
            "Sign in to Bitbucket from the profile's settings."
        ))
    }
}

import Foundation
import Testing
@testable import Core

@Suite("Grok account identity")
struct GrokAccountIdentityTests {
    private let grokHome = AgentAccountHome(
        provider: .grok,
        id: AgentAccountID("work"),
        directory: URL(filePath: "/support/AgentAccounts/grok/work"),
        isDefault: false
    )

    private func read(_ json: String) -> AgentAccountIdentity {
        AgentAccountIdentity.read(grokHome, identity: Data(json.utf8), credential: Data(json.utf8))
    }

    @Test func theIdentityAndTheCredentialAreTheSameAuthFileInTheAccountDirectory() {
        #expect(grokHome.identityPath == grokHome.directory.appending(path: "auth.json"))
        #expect(grokHome.credentialPath == grokHome.identityPath)
    }

    @Test func aGrokLoginIsNamedByItsEmailAndFirstName() {
        let identity = read(#"{"grok.com":{"email":"ada@lab.example","first_name":"Ada","auth_mode":"oauth"}}"#)

        #expect(identity.email == "ada@lab.example")
        #expect(identity.displayName == "Ada")
        #expect(identity.plan == nil)
    }

    @Test func anExpiryTheCliRefreshesOnItsOwnIsNotShown() {
        let identity = read(
            #"{"grok.com":{"email":"ada@lab.example","expires_at":"2026-01-01T00:00:00Z","refresh_token":"r"}}"#
        )

        #expect(identity.email == "ada@lab.example")
        #expect(identity.expiresAt == nil)
    }

    @Test func anExpiryWithNothingToRefreshItIsShown() {
        let identity = read(#"{"grok.com":{"email":"ada@lab.example","expires_at":"2026-01-01T00:00:00Z"}}"#)

        #expect(identity.expiresAt == ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z"))
    }

    @Test func aFileThatNamesNobodyCarriesNothing() {
        #expect(read(#"{"grok.com":{"auth_mode":"oauth"}}"#).isEmpty)
        #expect(read("not json").isEmpty)
        #expect(AgentAccountIdentity.read(grokHome, identity: nil, credential: nil).isEmpty)
    }
}

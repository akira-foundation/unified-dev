import Testing
@testable import Core

@Suite("Signing in from the profile sheet")
struct ProfileAccountSignInTests {
    @Test("the sheet offers a sign-in for each installed CLI that can keep a login apart, in the usual order")
    func offeredProviders() {
        let offered = ProfileAccountSignIn.providers(
            executables: [.grok, .codex, .claudeCode, .antigravity, .cursor, .openCode], codexStorageMode: .file
        )
        #expect(offered == [.claudeCode, .codex, .grok])
    }

    @Test("Grok gets a sign-in of its own, worded like the others")
    func grok() {
        #expect(ProfileAccountSignIn.providers(executables: [.grok], codexStorageMode: .keyring) == [.grok])
        #expect(ProfileAccountSignIn.title(for: .grok) == "Sign in with a Grok account\u{2026}")
    }

    @Test("a CLI that is not installed gets no sign-in")
    func missingExecutable() {
        #expect(ProfileAccountSignIn.providers(executables: [.codex], codexStorageMode: .file) == [.codex])
        #expect(ProfileAccountSignIn.providers(executables: [], codexStorageMode: .file).isEmpty)
    }

    @Test("Codex gets no sign-in while its login is kept in the keychain")
    func codexInTheKeychain() {
        #expect(!ProfileAccountSignIn.providers(executables: [.codex], codexStorageMode: .keyring).contains(.codex))
    }

    @Test("the button and the footer name the CLI and the profile the account goes to")
    func words() {
        #expect(ProfileAccountSignIn.title(for: .claudeCode) == "Sign in with a Claude Code account\u{2026}")
        #expect(ProfileAccountSignIn.footer(profileName: "Akira")
            == "An account signed in here belongs to Akira, whichever profile the window is showing.")
    }

    @Test("a profile that has just taken accounts of its own stays open to sign in, any other save closes")
    func staysOpen() {
        let akira = Profile(id: ProfileID("akira"), name: "Akira", folder: "akira", colour: Accent.all[1], symbol: "star")
        var new = ProfileDraft.new(among: [])
        var switching = ProfileDraft(editing: akira, accounts: .inherits)
        let alreadyOwn = ProfileDraft(editing: akira, accounts: .own)
        let newInheriting = ProfileDraft.new(among: [])
        new.accounts = .own
        switching.accounts = .own

        #expect(ProfileAccountSignIn.keepsSheetOpen(after: new))
        #expect(ProfileAccountSignIn.keepsSheetOpen(after: switching))
        #expect(!ProfileAccountSignIn.keepsSheetOpen(after: alreadyOwn))
        #expect(!ProfileAccountSignIn.keepsSheetOpen(after: newInheriting))
    }

    @Test("an account signed in from a profile's sheet goes to that profile, not to the one the window shows")
    func ownerIsTheEditedProfile() {
        let akira = ProfileID("akira")
        #expect(ProfileAccountSignIn.owner(editing: akira, active: .initial) == akira)
        #expect(ProfileAccountSignIn.owner(editing: nil, active: akira) == akira)
    }
}

@Suite("Where the profile sheet says its accounts are signed in")
struct ProfileAccountFootnoteTests {
    private let akira = Profile(id: ProfileID("akira"), name: "Akira", folder: "akira", colour: Accent.all[1], symbol: "star")

    @Test("a saved profile with accounts of its own points below, to its sign-in buttons")
    func savedOwnPointsBelow() {
        #expect(ProfileDraft(editing: akira, accounts: .own).accountsFootnote
            == "Has accounts of its own, signed in to below. An agent with no account here does not start.")
    }

    @Test("a new profile, or one switching to its own, says the sign-in comes once it is saved")
    func unsavedOwnWaitsForSave() {
        var new = ProfileDraft.new(among: [])
        new.accounts = .own
        var switching = ProfileDraft(editing: akira, accounts: .inherits)
        switching.accounts = .own
        #expect(new.accountsFootnote == "Has accounts of its own, signed in to here once the profile is saved. "
            + "An agent with no account here does not start.")
        #expect(switching.accountsFootnote == "Has accounts of its own, signed in to here once the profile is saved. "
            + "An agent with no account here does not start. "
            + "Projects that chose an account of Unified go back to this profile's default.")
    }
}

import Testing
import Foundation
@testable import Core

@Suite("Profile account words")
struct ProfileAccountWordsTests {
    private var standings: [AgentAccountStanding] {
        [
            AccountFixture.standing(AccountFixture.defaultClaude, email: "me@home.com"),
            AccountFixture.standing(AccountFixture.work, email: "me@client.com"),
        ]
    }

    private func group(_ scope: AgentAccountOptions.Scope, _ choices: AgentAccountChoices) throws -> AgentAccountOptions.Group {
        let made = AgentAccountOptions.make(scope: scope, choices: choices, standings: standings)
        return try #require(made.groups.first { $0.provider == .claudeCode })
    }

    @Test("a profile picks among its accounts and leaves the Mac's own login as its default entry")
    func profileOptions() throws {
        let none = try group(.profile, AgentAccountChoices())
        let chosen = try group(.profile, AgentAccountChoices(profile: [.claudeCode: AccountFixture.work.id]))

        #expect(none.inherit.title == "Default account")
        #expect(none.entries.map(\.title) == ["me@client.com"])
        #expect(none.note == "Every project in this profile runs the default Claude Code account unless it chooses another.")
        #expect(chosen.selected == .account(AccountFixture.work.id))
        #expect(chosen.note == "Every project in this profile runs Claude Code on me@client.com unless it chooses another.")
    }

    @Test("a profile's lost choice warns and says the default runs")
    func profileLost() throws {
        let made = try group(.profile, AgentAccountChoices(profile: [.claudeCode: AgentAccountID("gone")]))
        #expect(made.selected == .unavailable)
        #expect(made.note == "The account chosen for Claude Code in this profile is not available, so its projects run the default Claude Code account.")
        #expect(made.warns)
    }

    @Test("a project with no choice follows the profile, and is offered the default to leave it")
    func projectFollowsProfile() throws {
        let made = try group(.project, AgentAccountChoices(profile: [.claudeCode: AccountFixture.work.id]))
        #expect(made.inherit.title == "Same as profile")
        #expect(made.selected == .inherit)
        #expect(made.entries.map(\.title) == ["me@home.com", "me@client.com"])
        #expect(made.note == "Every workspace and chat in this project follows the profile and runs Claude Code on me@client.com.")
    }

    @Test("a project whose own choice is gone says it follows the profile instead")
    func projectLostFollowsProfile() throws {
        let made = try group(.project, AgentAccountChoices(
            project: [.claudeCode: AgentAccountID("gone")], profile: [.claudeCode: AccountFixture.work.id]
        ))
        #expect(made.note == "The account chosen for Claude Code in this project is not available, so every workspace and chat follows the profile.")
        #expect(made.warns)
    }

    @Test("a project under a profile whose choice is gone warns that the default runs")
    func projectUnderALostProfileChoice() throws {
        let made = try group(.project, AgentAccountChoices(profile: [.claudeCode: AgentAccountID("gone")]))
        #expect(made.note == "The account chosen for Claude Code in the profile is not available, so every workspace and chat runs its default account.")
        #expect(made.warns)
    }

    @Test("the composer names the profile when the account came from it, and the project's loss before it")
    func lines() {
        let fromProfile = AgentAccountChoice.resolve(
            provider: .claudeCode, project: nil, profile: AccountFixture.work.id, standings: standings
        )
        let afterLoss = AgentAccountChoice.resolve(
            provider: .claudeCode, project: AgentAccountID("gone"), profile: AccountFixture.work.id,
            standings: standings
        )
        let bothLost = AgentAccountChoice.resolve(
            provider: .claudeCode, project: AgentAccountID("b"), profile: AgentAccountID("c"), standings: standings
        )

        #expect(fromProfile.reason == .profile)
        #expect(AgentAccountLine.make(choice: fromProfile, provider: .claudeCode, standings: standings).sentence
            == "me@client.com runs here, chosen for the profile.")
        #expect(AgentAccountLine.make(choice: afterLoss, provider: .claudeCode, standings: standings).sentence
            == "me@client.com runs here, the profile's account, because the account chosen for the project is not available for Claude Code.")
        #expect(bothLost.isProjectChoiceLost && bothLost.isProfileChoiceLost)
        #expect(AgentAccountLine.make(choice: bothLost, provider: .claudeCode, standings: standings).sentence.hasSuffix(
            "because the accounts chosen for the project and for the profile are not available for Claude Code."
        ))
    }

    @Test("a profile with no account of its own says the agent does not start, and warns")
    func outsideProfile() {
        let choice = AgentAccountChoice.resolve(provider: .claudeCode, project: nil, standings: standings)
        let line = AgentAccountLine.make(choice: choice, provider: .claudeCode, standings: standings, outsideProfile: true)
        let inUnified = AgentAccountLine.make(choice: choice, provider: .claudeCode, standings: standings)

        #expect(line.title == AgentAccountLine.unavailableTitle)
        #expect(line.sentence == "Claude Code does not start here, because this profile has accounts of its own and "
            + "it has no Claude Code account chosen. "
            + "Choose one for the project, or a default for the profile in Profile Settings.")
        #expect(line.warns)
        #expect(!inUnified.warns)
    }

    private func panel(_ owner: AgentAccountPanel.Owner, standings: [AgentAccountStanding]? = nil) -> AgentAccountPanel {
        AgentAccountPanel.make(
            provider: .claudeCode, standings: standings ?? self.standings, codexStorageMode: .file, owner: owner
        )
    }

    @Test("Settings says which account is the profile's default, and what the Mac's own login is for")
    func panelRoles() {
        let made = panel(AgentAccountPanel.Owner(
            name: "Unified", holderName: "Unified", inherits: false,
            refusesWithoutAccount: false, defaultAccount: AccountFixture.work.id
        ))
        #expect(made.rows.map(\.note) == [
            "This Mac's own login, used when the default account of Unified is not available.",
            "The default account of Unified, used wherever a project has not chosen another.",
        ])
        #expect(made.footer == nil)
    }

    @Test("Settings tells a profile that inherits where its accounts are, and an empty one what it runs")
    func panelFooters() {
        let heir = panel(AgentAccountPanel.Owner(
            name: "Heir", holderName: "Unified", inherits: true,
            refusesWithoutAccount: false, defaultAccount: nil
        ))
        let empty = panel(
            AgentAccountPanel.Owner(
                name: "Akira", holderName: "Akira", inherits: false,
                refusesWithoutAccount: true, defaultAccount: nil
            ),
            standings: []
        )
        #expect(heir.footer == "Heir uses the accounts of Unified. Choose its own in Profile Settings.")
        #expect(empty.footer == "Akira has no Claude Code account of its own, so its projects do not start Claude Code until one is added.")
    }

    @Test("a profile that falls back to the Mac is told that, not that its projects stop")
    func panelFooterForAProfileThatFallsBackToTheMac() {
        let empty = panel(
            AgentAccountPanel.Owner(
                name: "Unified", holderName: "Unified", inherits: false,
                refusesWithoutAccount: false, defaultAccount: nil
            ),
            standings: []
        )
        #expect(empty.footer == "Unified has no Claude Code account of its own, "
            + "so its projects run Claude Code under this Mac's own login.")
    }

    @Test("the footer of an empty panel follows the launch, agent by agent")
    func panelFooterFollowsTheLaunch() {
        let akira = Profile(id: ProfileID("akira"), name: "Akira", folder: "akira", colour: Accent.all[1], symbol: "star")
        let book = AgentAccountChoiceBook(accounts: ProfileAccounts(sources: [akira.id: .own]))
        func footer(_ provider: AgentKind, in profile: ProfileID) -> String? {
            AgentAccountPanel.make(
                provider: provider, in: profile, profiles: [akira], book: book,
                standings: standings, codexStorageMode: .file
            ).footer
        }

        #expect(footer(.claudeCode, in: akira.id) == "Akira has no Claude Code account of its own, "
            + "so its projects do not start Claude Code until one is added.")
        #expect(footer(.grok, in: akira.id) == "Akira has no Grok account of its own, "
            + "so its projects do not start Grok until one is added.")
        #expect(footer(.grok, in: .initial) == "Unified has no Grok account of its own, "
            + "so its projects run Grok under this Mac's own login.")
        #expect(footer(.cursor, in: akira.id) == nil)
        #expect(footer(.openCode, in: .initial) == nil)
    }

    @Test("the panel lists only the active profile's accounts and names the projects that chose each")
    func panelForAProfile() throws {
        let akira = Profile(id: ProfileID("akira"), name: "Akira", folder: "akira", colour: Accent.all[1], symbol: "star")
        let site = Repo(name: "Site", path: "/code/site", profileID: akira.id)
        let shop = Repo(name: "Shop", path: "/code/shop", profileID: akira.id)
        let book = AgentAccountChoiceBook(
            repos: [site.id: [.claudeCode: AccountFixture.work.id], shop.id: [.claudeCode: AccountFixture.work.id]],
            repoProfiles: [site.id: akira.id, shop.id: akira.id],
            accounts: ProfileAccounts(owners: [AccountFixture.work.id: akira.id], sources: [akira.id: .own])
        )
        let made = AgentAccountPanel.make(
            provider: .claudeCode, in: akira.id, profiles: [akira], repos: [site, shop], book: book,
            standings: standings, codexStorageMode: .file
        )
        let row = try #require(made.rows.first)

        #expect(made.rows.map(\.id) == [AccountFixture.work.id])
        #expect(row.removal?.message.contains("Shop and Site go back to the default account of the profile.") == true)
    }

    @Test("removing an account nobody chose says anything that used it goes back to the default")
    func removalWithoutChoosers() {
        let warning = AgentAccountRemoval.warning(forAccountNamed: "Client", provider: .claudeCode, folderExists: true)
        #expect(warning.message.contains(" Anything that used this account goes back to the default account."))
    }

    @Test("a new profile inherits until the owner says otherwise, and Unified offers no choice")
    func drafts() {
        let unified = Profile(id: .initial, name: "Unified", folder: "unified", colour: Accent.all[0], symbol: "star")
        let akira = Profile(id: ProfileID("akira"), name: "Akira", folder: "akira", colour: Accent.all[1], symbol: "star")
        var switching = ProfileDraft(editing: akira, accounts: .inherits)
        switching.accounts = .own

        #expect(ProfileDraft.new(among: [unified]).accounts == .inherits)
        #expect(!ProfileDraft.new(among: [unified]).accountsChanged)
        #expect(!ProfileDraft(editing: unified, accounts: .own).choosesAccounts)
        #expect(switching.accountsChanged)
        #expect(switching.accountsFootnote.hasSuffix("Projects that chose an account of Unified go back to this profile's default."))
        #expect(ProfileDraft(editing: akira, accounts: .inherits).accountsFootnote
            == "Uses the accounts of Unified and follows any change made there.")
    }

    @Test("the notices name the projects whose choice was cleared and the agent a moved project lost")
    func notices() {
        let akira = Profile(id: ProfileID("akira"), name: "Akira", folder: "akira", colour: Accent.all[1], symbol: "star")
        let site = Repo(name: "Site", path: "/code/site")
        let shop = Repo(name: "Shop", path: "/code/shop")
        let book = AgentAccountChoiceBook(
            repos: [site.id: [.claudeCode: AccountFixture.personal.id]],
            accounts: ProfileAccounts(sources: [akira.id: .own])
        )

        #expect(ProfileAccountNotice.cleared([site.id, shop.id], repos: [site, shop])
            == "Site and Shop go back to the profile's default account, because the account chosen there is no longer one this profile uses.")
        #expect(ProfileAccountNotice.cleared([], repos: [site]) == nil)
        #expect(ProfileAccountNotice.moved(site, to: akira, holderName: "Akira", book: book)
            == "Site now runs the default Claude Code account of Akira, because the account it chose is not one Akira uses.")
        #expect(ProfileAccountNotice.moved(shop, to: akira, holderName: "Akira", book: book) == nil)
    }

    @Test("a profile with accounts of its own offers no account as its last resort, and warns that nothing starts")
    func profileOptionsOutsideUnified() throws {
        let made = AgentAccountOptions.make(
            scope: .profile, choices: AgentAccountChoices(), standings: standings, outsideProfile: true
        )
        let claude = try #require(made.groups.first)
        #expect(claude.inherit.title == "No account")
        #expect(claude.note == "No project in this profile starts Claude Code unless it chooses an account.")
        #expect(claude.warns)
    }
}

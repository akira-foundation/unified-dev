import Core
import Observation

@MainActor
@Observable
final class GitHostingModel {
    private(set) var thisMac: [ForgeKind: GitHostingAccount] = [:]
    private(set) var own: [ForgeKind: [ProfileID: GitHostingAccount]] = [:]
    private(set) var signingOut: ForgeKind?
    var failure: String?

    @ObservationIgnored private let seeded = PreviewScenario.GitHosting.seeded()
    @ObservationIgnored private var seededSignedOut: Set<ForgeKind> = []

    var isSeeded: Bool { seeded != nil }

    func account(on host: ForgeKind) -> GitHostingAccount {
        thisMac[host] ?? .checking
    }

    func rows(on host: ForgeKind, profiles: [Profile], logins: ProfileGitHubLogins) -> [GitHostingProfileRow] {
        GitHosting.rows(
            on: host, profiles: profiles, logins: logins, thisMac: account(on: host), own: own[host] ?? [:]
        )
    }

    func load(store: Store?, profiles: [Profile]) async {
        let logins = store?.gitHubLogins()
        for host in GitHosting.hosts {
            let owners = logins.map { GitHosting.profilesWithOwnLogin(on: host, profiles: profiles, logins: $0) } ?? []
            thisMac[host] = await read(host, login: .thisMac, profileName: nil)
            var found: [ProfileID: GitHostingAccount] = [:]
            for id in owners {
                let name = profiles.first { $0.id == id }?.name ?? id.rawValue
                found[id] = await read(host, login: store?.gitHubLogin(for: id) ?? .thisMac, profileName: name)
            }
            own[host] = found
        }
    }

    func signOut(_ host: ForgeKind) async {
        guard GitHosting.canSignOut(host, account: account(on: host)), let user = account(on: host).user else { return }
        signingOut = host
        failure = nil
        defer { signingOut = nil }
        if isSeeded {
            seededSignedOut.insert(host)
            thisMac[host] = .signedOut
            return
        }
        let result = switch host {
        case .gitHub: await GitHub.signOut(user: user)
        case .bitbucket: await Bitbucket.signOut(directory: AgentScratchDirectory.current())
        }
        if result?.ok != true {
            let detail = result.map { ($0.stderr.isEmpty ? $0.stdout : $0.stderr).trimmingCharacters(in: .whitespacesAndNewlines) }
            failure = GitHostingWording.signOutFailure(host, detail: detail)
        }
        if host == .gitHub { await GitHubAvailability.shared.check(login: .thisMac, force: true) }
        thisMac[host] = await read(host, login: .thisMac, profileName: nil)
    }

    func restoreSeededSignIn(_ host: ForgeKind) {
        seededSignedOut.remove(host)
        thisMac[host] = seeded?.host(host)?.thisMacAccount ?? .signedOut
    }

    private func read(_ host: ForgeKind, login: GitHubLogin, profileName: String?) async -> GitHostingAccount {
        if let seeded {
            guard let seededHost = seeded.host(host) else { return .signedOut }
            guard let profileName else {
                return seededSignedOut.contains(host) ? .signedOut : seededHost.thisMacAccount
            }
            return seededHost.account(ofProfileNamed: profileName)
        }
        switch host {
        case .gitHub:
            let state = await GitHubAvailability.shared.check(login: login, force: true)
            guard state == .ready else { return state == .notInstalled ? .notInstalled : .signedOut }
            return .signedIn(await GitHub.signedInUser(login: login) ?? GitHostingWording.signedInUnnamed)
        case .bitbucket:
            let account = await Bitbucket.account(login: login.bitbucket, directory: AgentScratchDirectory.current())
            if let account { return .signedIn(account.user ?? GitHostingWording.signedInUnnamed) }
            return Shell.which(Bitbucket.executable) == nil ? .notInstalled : .signedOut
        }
    }
}

import Foundation
import Observation
import Core

@MainActor
@Observable
final class AgentAccountsModel {
    struct Creation: Identifiable {
        let id = UUID()
        let reservation: AgentAccountReservation
        let profile: ProfileID

        var plan: AgentAccountCreation { reservation.plan }
    }

    enum Activity: Equatable {
        case idle
        case checkingSessions
        case confirmingSignIn
    }

    private(set) var standings: [AgentAccountStanding] = []
    private(set) var orphans: [AgentAccountHome] = []
    private(set) var codexStorageMode: CodexAuthStorageMode = .file
    private(set) var activity = Activity.idle
    private(set) var failure: String?
    private(set) var removalNotice: AgentAccountRemovalNotice?
    private(set) var book = AgentAccountChoiceBook()

    @ObservationIgnored private var lastAskedAt: Date?
    @ObservationIgnored private var answers: [AgentAccountID: AgentAccountLiveness.CliReport] = [:]
    @ObservationIgnored private var creatingDirectory: URL?

    func panel(for provider: AgentKind, in profile: ProfileID, profiles: [Profile], repos: [Repo]) -> AgentAccountPanel {
        AgentAccountPanel.make(
            provider: provider, in: profile, profiles: profiles, repos: repos, book: book,
            standings: standings, orphans: orphans, codexStorageMode: codexStorageMode
        )
    }

    func dismissFailure() {
        failure = nil
    }

    func dismissRemovalNotice() {
        removalNotice = nil
    }

    func reload(store: Store?) async {
        guard let store else { return }
        do {
            let rows = try await store.agentAccounts()
            let defaults = SpendAccounts.defaultHomes()
            let plain = await AgentAccountInventory.standingsWithoutAsking(rows: rows, defaults: defaults)
            await adopt(plain.map { $0.reporting(answers) }, rows: rows, defaults: defaults, store: store)
        } catch {
            failure = "Could not read the accounts: \(error.readableMessage)"
        }
    }

    func askIfDue(after gap: TimeInterval, executables: [AgentKind: String], store: Store?) async {
        guard let store, activity == .idle,
              QuotaPollSchedule.isDue(lastAskedAt: lastAskedAt, at: Date(), after: gap)
        else { return }
        activity = .checkingSessions
        let previous = lastAskedAt
        lastAskedAt = Date()
        defer { activity = .idle }
        let defaults = SpendAccounts.defaultHomes()
        let liveness = AgentAccountLiveness.using(executables: executables)
        guard let rows = try? await store.agentAccounts(),
              let asked = await AgentAccountInventory.standingsUnlessCancelled(rows: rows, defaults: defaults, report: {
                  await liveness.report(for: $0)
              })
        else {
            lastAskedAt = previous
            return
        }
        answers = Dictionary(asked.map { ($0.home.id, $0.cliReport) }, uniquingKeysWith: { _, latest in latest })
        await adopt(asked, rows: rows, defaults: defaults, store: store)
    }

    func confirmSignIn(of account: AgentAccountID, executables: [AgentKind: String], store: Store?) async {
        if removalNotice?.account == account { removalNotice = nil }
        answers[account] = nil
        lastAskedAt = nil
        await reload(store: store)
        await askIfDue(after: 0, executables: executables, store: store)
    }

    func beginCreation(provider: AgentKind, label: String, profile: ProfileID, store: Store?) async -> Creation? {
        guard let store, let clean = AgentAccountCreation.cleanLabel(label) else { return nil }
        let support = Self.support(of: store)
        do {
            let reservation = try AgentAccountCreation.reserve(
                provider: provider,
                label: clean,
                existing: try await store.agentAccounts().map(\.id),
                support: support
            )
            failure = nil
            removalNotice = nil
            creatingDirectory = reservation.plan.directory
            return Creation(reservation: reservation, profile: profile)
        } catch {
            failure = "Could not start the sign-in: \(error.readableMessage)"
            return nil
        }
    }

    func finishCreation(
        _ creation: Creation,
        exit: TerminalExit?,
        executables: [AgentKind: String],
        store: Store?
    ) async {
        let plan = creation.plan
        if exit == .exited(0) { activity = .confirmingSignIn }
        defer { activity = .idle }
        let liveness = AgentAccountLiveness.using(executables: executables)
        let concluded = await AgentAccountInventory.concluding(plan, exit: exit, report: {
            await liveness.report(for: $0)
        })
        creatingDirectory = nil
        guard let standing = concluded else {
            failure = "The sign-in for \(plan.label) did not complete, so no account was added."
            await creation.reservation.discardOnceReleased()
            await reload(store: store)
            return
        }
        guard let store else {
            failure = "\(plan.label) is signed in but could not be saved, because the database is not open."
            return
        }
        do {
            let owner = try await store.profileAccounts().holder(for: creation.profile)
            try await store.add(AgentAccountRow(
                id: plan.id, provider: plan.provider, directory: plan.directory.path, label: plan.label,
                profileID: owner
            ))
        } catch {
            failure = "\(plan.label) is signed in but could not be saved: \(error.readableMessage)"
            await reload(store: store)
            return
        }
        answers[plan.id] = standing.cliReport
        failure = nil
        await reload(store: store)
    }

    func remove(_ row: AgentAccountPanel.Row, store: Store?) async {
        guard let store else { return }
        let support = Self.support(of: store)
        removalNotice = nil
        failure = nil
        do {
            try await AgentAccountRemoval.remove(row, support: support, store: store, keychain: .login)
            if !row.isUnfinished { answers[row.id] = nil }
        } catch {
            let notice = AgentAccountRemovalNotice.after(error, removing: row)
            if notice.forgotTheAccount { answers[row.id] = nil }
            removalNotice = notice
        }
        await reload(store: store)
    }

    private func adopt(
        _ latest: [AgentAccountStanding],
        rows: [AgentAccountRow],
        defaults: [AgentAccountHome],
        store: Store
    ) async {
        if let read = try? await store.agentAccountChoices(), book != read { book = read }
        if standings != latest { standings = latest }
        let found = AgentAccountOrphans.find(
            support: Self.support(of: store), rows: rows, defaults: defaults,
            excluding: creatingDirectory.map { [$0] } ?? []
        )
        if orphans != found { orphans = found }
        let mode = AgentAccountInventory.codexStorageMode(among: defaults)
        if codexStorageMode != mode { codexStorageMode = mode }
    }

    private static func support(of store: Store) -> URL {
        URL(filePath: store.path).deletingLastPathComponent()
    }
}

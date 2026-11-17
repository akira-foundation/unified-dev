import SwiftUI
import Observation
import Core

@MainActor
@Observable
final class GitHubAvailability {
    static let shared = GitHubAvailability()

    enum State: Equatable {
        case unknown
        case ready
        case notInstalled
        case signedOut

        init(_ access: GitHubAccess) {
            switch access {
            case .ready: self = .ready
            case .notInstalled: self = .notInstalled
            case .signedOut: self = .signedOut
            }
        }

        var isUsable: Bool { self != .notInstalled && self != .signedOut }
    }

    private(set) var states: [GitHubLogin: State] = [:]

    private static let negativeLifetime = Duration.seconds(120)

    private var probes: [GitHubLogin: Task<State, Never>] = [:]
    private var answeredAt: [GitHubLogin: ContinuousClock.Instant] = [:]

    func state(for login: GitHubLogin) -> State {
        states[login] ?? .unknown
    }

    @discardableResult
    func check(directory: String?, force: Bool = false) async -> State {
        await check(login: await GitHub.login(forDirectory: directory), force: force)
    }

    @discardableResult
    func check(login: GitHubLogin, force: Bool = false) async -> State {
        let state = state(for: login)
        if force {
            probes[login]?.cancel()
            probes[login] = nil
            answeredAt[login] = nil
        } else {
            if state == .ready { return .ready }
            if let answered = answeredAt[login], answered.duration(to: .now) < Self.negativeLifetime,
               !state.isUsable {
                return state
            }
            if let probe = probes[login] { return await probe.value }
        }

        let task = Task { State(await GitHub.access(login: login)) }
        probes[login] = task
        let answer = await task.value
        guard probes[login] == task else { return answer }
        probes[login] = nil
        answeredAt[login] = .now
        states[login] = answer
        return answer
    }
}

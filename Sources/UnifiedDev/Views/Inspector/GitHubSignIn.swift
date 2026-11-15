import SwiftUI
import Observation
import Core

@MainActor
@Observable
final class GitHubSignIn {
    static let shared = GitHubSignIn()

    struct Request: Identifiable, Equatable {
        let id = UUID()
        var access: GitHubAvailability.State
        var directory: String
        var login: GitHubLogin

        static func == (lhs: Request, rhs: Request) -> Bool { lhs.id == rhs.id }
    }

    var request: Request? {
        didSet {
            guard request == nil else { return }
            pending = nil
        }
    }

    @ObservationIgnored private var pending: (@MainActor () -> Void)?

    func run(directory: String, action: @escaping @MainActor () -> Void) {
        Task {
            if await Forge.kind(forDirectory: directory) == .bitbucket {
                action()
                return
            }
            let login = await GitHub.login(forDirectory: directory)
            let state = await GitHubAvailability.shared.check(login: login)
            guard state != .ready else {
                action()
                return
            }
            pending = action
            request = Request(access: state, directory: directory, login: login)
        }
    }

    func present(directory: String) {
        run(directory: directory) {}
    }

    func finish(connected: Bool) {
        let action = pending
        pending = nil
        request = nil
        if connected { action?() }
    }
}

import Foundation
import Synchronization

public final class ClaudeAccountActivity: Sendable {
    public static let shared = ClaudeAccountActivity()

    private struct State {
        var runs: [AgentAccountID: Int] = [:]
        var probing: Set<AgentAccountID> = []
        var waiting: [AgentAccountID: [ClaudeRunTicket]] = [:]
    }

    private let state = Mutex(State())

    static let exitGrace: Duration = .seconds(2)

    public init() {}

    public func beginRun(_ account: AgentAccountID, ticket: ClaudeRunTicket = ClaudeRunTicket()) async -> ClaudeRunLease? {
        let admitted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let answer = state.withLock { state -> Bool? in
                    switch ticket.wait(for: account, continuation: continuation, probing: state.probing.contains(account)) {
                    case .withdrawn: return false
                    case .admitted:
                        state.runs[account, default: 0] += 1
                        return true
                    case .waiting:
                        state.waiting[account, default: []].append(ticket)
                        return nil
                    }
                }
                if let answer { continuation.resume(returning: answer) }
            }
        } onCancel: {
            withdraw(ticket)
        }
        guard admitted else { return nil }
        return ClaudeRunLease { [self] in endRun(account) }
    }

    func holding<Answer: Sendable>(
        _ account: AgentAccountHome?,
        _ work: @Sendable () async -> Answer
    ) async -> Answer? {
        guard let lease = await beginRun(ClaudeResolvedModel.accountID(account)) else { return nil }
        defer { lease.end() }
        return await work()
    }

    public func withdraw(_ ticket: ClaudeRunTicket) {
        let continuation = state.withLock { state -> CheckedContinuation<Bool, Never>? in
            guard let (account, continuation) = ticket.withdraw() else { return nil }
            state.waiting[account]?.removeAll { $0 === ticket }
            if state.waiting[account]?.isEmpty == true { state.waiting[account] = nil }
            return continuation
        }
        continuation?.resume(returning: false)
    }

    public func isRunning(_ account: AgentAccountID) -> Bool {
        state.withLock { ($0.runs[account] ?? 0) > 0 || !($0.waiting[account] ?? []).isEmpty }
    }

    func waitingRuns(_ account: AgentAccountID) -> Int {
        state.withLock { $0.waiting[account]?.count ?? 0 }
    }

    func beginProbe(_ account: AgentAccountID) -> Bool {
        state.withLock { state in
            guard (state.runs[account] ?? 0) == 0,
                  (state.waiting[account] ?? []).isEmpty,
                  !state.probing.contains(account) else { return false }
            state.probing.insert(account)
            return true
        }
    }

    func endProbe(_ account: AgentAccountID) {
        let admitted = state.withLock { state -> [CheckedContinuation<Bool, Never>] in
            state.probing.remove(account)
            let waiting = (state.waiting.removeValue(forKey: account) ?? []).compactMap { $0.admit() }
            if !waiting.isEmpty { state.runs[account, default: 0] += waiting.count }
            return waiting
        }
        for continuation in admitted { continuation.resume(returning: true) }
    }

    private func endRun(_ account: AgentAccountID) {
        state.withLock { state in
            let remaining = (state.runs[account] ?? 0) - 1
            state.runs[account] = remaining > 0 ? remaining : nil
        }
    }
}

public final class ClaudeRunTicket: Sendable {
    enum Placement { case admitted, waiting, withdrawn }

    private enum Phase {
        case fresh
        case waiting(AgentAccountID, CheckedContinuation<Bool, Never>)
        case admitted
        case withdrawn
    }

    private let phase = Mutex(Phase.fresh)

    public init() {}

    func wait(for account: AgentAccountID, continuation: CheckedContinuation<Bool, Never>, probing: Bool) -> Placement {
        phase.withLock { phase in
            guard case .fresh = phase else { return .withdrawn }
            guard probing else {
                phase = .admitted
                return .admitted
            }
            phase = .waiting(account, continuation)
            return .waiting
        }
    }

    func withdraw() -> (AgentAccountID, CheckedContinuation<Bool, Never>)? {
        phase.withLock { phase in
            switch phase {
            case .fresh:
                phase = .withdrawn
                return nil
            case .waiting(let account, let continuation):
                phase = .withdrawn
                return (account, continuation)
            case .admitted, .withdrawn:
                return nil
            }
        }
    }

    func admit() -> CheckedContinuation<Bool, Never>? {
        phase.withLock { phase in
            guard case .waiting(_, let continuation) = phase else { return nil }
            phase = .admitted
            return continuation
        }
    }
}

public final class ClaudeRunLease: Sendable {
    private let release: Mutex<(@Sendable () -> Void)?>

    init(release: @escaping @Sendable () -> Void) {
        self.release = Mutex(release)
    }

    public func end() {
        let pending = release.withLock { held -> (@Sendable () -> Void)? in
            defer { held = nil }
            return held
        }
        pending?()
    }

    deinit { end() }
}

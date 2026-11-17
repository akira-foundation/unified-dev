import Foundation
import Synchronization
import os

public enum StoreDomain: String, Sendable, Hashable, CaseIterable {
    case repos
    case workspaces
    case sessions
    case messages
    case terminalTabs = "terminal_tabs"
    case settings
    case drafts
    case reviewComments = "review_comments"
    case reviewedFiles = "reviewed_files"
    case permissionGrants = "permission_grants"
    case permissionAsks = "permission_asks"
    case agentQuotas = "agent_quotas"
    case quickPrompts = "quick_prompt"
    case workspaceMessages = "workspace_messages"
    case workSuggestions = "work_suggestions"
    case repoAgentAccounts = "repo_agent_accounts"
    case profileAgentAccounts = "profile_agent_accounts"
    case inboxNotifications = "inbox_notifications"
    case diffStats = "diff_stats"

    public static let projectsWorkspacesAndTheirAccounts: Set<StoreDomain> = [
        .repos, .workspaces, .repoAgentAccounts, .profileAgentAccounts,
    ]

    public static let projectListFeed = projectsWorkspacesAndTheirAccounts.union([.diffStats])
}

public enum ProjectListRefresh: Sendable, Equatable {
    case reload
    case diffStatsOnly

    public init(answering batch: Set<StoreDomain>) {
        self = batch.isDisjoint(with: StoreDomain.projectsWorkspacesAndTheirAccounts) ? .diffStatsOnly : .reload
    }
}

public final class StoreChangeHub: Sendable {
    private struct Subscriber {
        let interest: Set<StoreDomain>
        var pending: Set<StoreDomain>
        let wake: AsyncStream<Void>.Continuation
    }

    private struct State {
        var subscribers: [Int: Subscriber] = [:]
        var nextID = 0
        var windowStart: ContinuousClock.Instant?
        var windowCount = 0
    }

    private let state = Mutex(State())

    private static let runawayWindow = Duration.seconds(5)
    private static let runawayCount = 1_000

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.akira.unifieddev",
        category: "store"
    )

    static func shared(forPath path: String) -> StoreChangeHub {
        guard path != ":memory:" else { return StoreChangeHub() }
        let key = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return registry.withLock { registry in
            if let existing = registry[key]?.hub { return existing }
            let hub = StoreChangeHub()
            registry[key] = WeakHub(hub: hub)
            registry = registry.filter { $0.value.hub != nil }
            return hub
        }
    }

    private struct WeakHub {
        weak var hub: StoreChangeHub?
    }

    private static let registry = Mutex<[String: WeakHub]>([:])

    func publish(_ domains: Set<StoreDomain>) {
        guard !domains.isEmpty else { return }
        var runaway: Int?
        let waking = state.withLock { state -> [AsyncStream<Void>.Continuation] in
            runaway = countTowardsRunaway(&state)
            var waking: [AsyncStream<Void>.Continuation] = []
            for (id, subscriber) in state.subscribers {
                let relevant = domains.intersection(subscriber.interest)
                guard !relevant.isEmpty else { continue }
                let wasIdle = state.subscribers[id]?.pending.isEmpty ?? false
                state.subscribers[id]?.pending.formUnion(relevant)
                if wasIdle, let continuation = state.subscribers[id]?.wake {
                    waking.append(continuation)
                }
            }
            return waking
        }
        for continuation in waking { continuation.yield() }
        if let runaway {
            Self.log.error(
                """
                \(runaway, privacy: .public) store commits in the last \
                \(Self.runawayWindow.components.seconds, privacy: .public) seconds. Something \
                handling a change is very likely writing back into the store it is listening to. \
                See the two rules on StoreChangeHub.
                """
            )
        }
    }

    private func countTowardsRunaway(_ state: inout State) -> Int? {
        let now = ContinuousClock.now
        guard let started = state.windowStart else {
            state.windowStart = now
            state.windowCount = 1
            return nil
        }
        state.windowCount += 1
        guard now - started >= Self.runawayWindow else { return nil }
        let count = state.windowCount
        state.windowStart = now
        state.windowCount = 0
        return count > Self.runawayCount ? count : nil
    }

    fileprivate func subscribe(to interest: Set<StoreDomain>) -> (id: Int, wakes: AsyncStream<Void>) {
        let (wakes, continuation) = AsyncStream.makeStream(
            of: Void.self, bufferingPolicy: .bufferingNewest(1)
        )
        let id = state.withLock { state -> Int in
            state.nextID += 1
            state.subscribers[state.nextID] = Subscriber(
                interest: interest, pending: [], wake: continuation
            )
            return state.nextID
        }
        continuation.onTermination = { [weak self] _ in self?.unsubscribe(id) }
        return (id, wakes)
    }

    fileprivate func drain(_ id: Int) -> Set<StoreDomain> {
        state.withLock { state in
            guard let pending = state.subscribers[id]?.pending else { return [] }
            state.subscribers[id]?.pending = []
            return pending
        }
    }

    var subscriberCount: Int {
        state.withLock { $0.subscribers.count }
    }

    private func unsubscribe(_ id: Int) {
        _ = state.withLock { $0.subscribers.removeValue(forKey: id) }
    }
}

public struct StoreChanges: AsyncSequence, Sendable {
    public typealias Element = Set<StoreDomain>

    private let hub: StoreChangeHub
    private let interest: Set<StoreDomain>

    init(hub: StoreChangeHub, interest: Set<StoreDomain>) {
        self.hub = hub
        self.interest = interest
    }

    public func makeAsyncIterator() -> Iterator {
        let subscription = hub.subscribe(to: interest)
        return Iterator(hub: hub, id: subscription.id, wakes: subscription.wakes.makeAsyncIterator())
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let hub: StoreChangeHub
        private let id: Int
        private var wakes: AsyncStream<Void>.Iterator

        init(hub: StoreChangeHub, id: Int, wakes: AsyncStream<Void>.Iterator) {
            self.hub = hub
            self.id = id
            self.wakes = wakes
        }

        public mutating func next() async -> Set<StoreDomain>? {
            while await wakes.next() != nil {
                let batch = hub.drain(id)
                if !batch.isEmpty { return batch }
            }
            return nil
        }
    }
}

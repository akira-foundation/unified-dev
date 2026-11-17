import Foundation
import Synchronization

public protocol SessionRunner: Actor {
    nonisolated var agentKind: AgentKind { get }

    nonisolated var events: AsyncStream<AgentEvent> { get }
    nonisolated var presentationFeed: AgentPresentationFeed? { get }
    nonisolated var storedMessages: StoredMessageRelay? { get }

    var isProcessAlive: Bool { get }
    var hasStoppedWriting: Bool { get }
    func evictIfIdle(for duration: Duration) async -> Bool

    func send(_ text: String, recording: Data?) async throws
    func sendDelivery(_ delivery: Delivery) async throws
    nonisolated var supportsConversationRewind: Bool { get }
    func rewind(beforeTurnID: String) async throws
    func turnPresence(_ turnID: String) async throws -> ConversationTurnPresence

    nonisolated func cancelNow()

    nonisolated func terminateNow()

    func answer(requestID: String, decision: PermissionDecision) async

    nonisolated var stopsBackgroundTasks: Bool { get }
    func stopTask(_ id: SubagentID) async -> Bool
}

extension SessionRunner {
    public nonisolated var supportsConversationRewind: Bool { false }
    public func rewind(beforeTurnID: String) async throws { throw ConversationRewindError.unsupported }
    public func turnPresence(_ turnID: String) async throws -> ConversationTurnPresence {
        throw ConversationRewindError.unsupported
    }
    public func evictIfIdle(for duration: Duration) async -> Bool { false }
    public nonisolated var presentationFeed: AgentPresentationFeed? { nil }
    public nonisolated var storedMessages: StoredMessageRelay? { nil }
    public nonisolated var stopsBackgroundTasks: Bool { false }
    public func stopTask(_ id: SubagentID) async -> Bool { false }
    public func sendDelivery(_ delivery: Delivery) async throws {
        try await send(delivery.sent, recording: delivery.crewPayload)
    }

    public func send(_ text: String) async throws {
        try await send(text, recording: nil)
    }
}

public final class EventFanout<Element: Sendable>: Sendable {
    private struct State {
        var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
        var finished = false
    }

    private let state = Mutex(State())

    public init() {}

    public func stream() -> AsyncStream<Element> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let registered = state.withLock { state -> Bool in
                guard !state.finished else { return false }
                state.continuations[id] = continuation
                return true
            }
            guard registered else {
                continuation.finish()
                return
            }
            continuation.onTermination = { [weak self] _ in
                self?.unregister(id)
            }
        }
    }

    public func yield(_ element: Element) {
        for target in subscribers() { target.yield(element) }
    }

    public func finish() {
        for target in removeAll() { target.finish() }
    }

    private func unregister(_ id: UUID) {
        state.withLock { $0.continuations[id] = nil }
    }

    private func subscribers() -> [AsyncStream<Element>.Continuation] {
        state.withLock { Array($0.continuations.values) }
    }

    private func removeAll() -> [AsyncStream<Element>.Continuation] {
        state.withLock { state in
            state.finished = true
            let all = Array(state.continuations.values)
            state.continuations = [:]
            return all
        }
    }
}

extension AgentRunner: SessionRunner {
    public nonisolated var agentKind: AgentKind { .claudeCode }

    public var isProcessAlive: Bool { isRunning }

    public nonisolated func terminateNow() { cancelNow() }

    public nonisolated var stopsBackgroundTasks: Bool { true }
}

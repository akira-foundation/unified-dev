import Foundation

public struct SideConversationLifecycle: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case opening(generation: Int, session: SessionID?)
        case open(SessionID)
    }

    public struct Arrival: Equatable, Sendable {
        public var quotes: [String]
        public var questions: [String]

        public init(quotes: [String] = [], questions: [String] = []) {
            self.quotes = quotes
            self.questions = questions
        }
    }

    public struct Opening: Equatable, Sendable {
        public var generation: Int
        public var keeping: SessionID?
    }

    public enum Start: Equatable, Sendable {
        case wait
        case resume(SessionID, Arrival)
        case open(Opening)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var isShown = false
    public private(set) var pending = Arrival()
    private var generation = 0

    public init() {}

    public var isOpening: Bool {
        if case .opening = phase { return true }
        return false
    }

    public var sessionID: SessionID? {
        if case .open(let id) = phase { return id }
        return nil
    }

    public var isPresent: Bool { phase != .idle || isShown }

    public mutating func start(question: String = "", quoting: String = "", fresh: Bool = false) -> Start {
        isShown = true
        if !quoting.isEmpty { pending.quotes.append(quoting) }
        if !question.isEmpty { pending.questions.append(question) }
        switch phase {
        case .opening:
            return .wait
        case .open(let id) where !fresh:
            return .resume(id, takeArrival())
        case .open(let id):
            return .open(beginOpening(keeping: id))
        case .idle:
            return .open(beginOpening(keeping: nil))
        }
    }

    public mutating func opened(_ id: SessionID, generation: Int) -> Bool {
        guard phase == .opening(generation: generation, session: nil) else { return false }
        phase = .opening(generation: generation, session: id)
        return true
    }

    public mutating func ready(generation: Int) -> Arrival? {
        guard case .opening(generation, let session?) = phase else { return nil }
        phase = .open(session)
        return takeArrival()
    }

    public enum Failure: Equatable, Sendable {
        case stale
        case current(arrived: SessionID?)
    }

    public mutating func failed(generation: Int) -> Failure {
        guard case .opening(generation, let arrived) = phase else { return .stale }
        phase = .idle
        return .current(arrived: arrived)
    }

    public mutating func keepFailed(generation: Int, restoring id: SessionID) -> Arrival? {
        guard case .opening(generation, nil) = phase else { return nil }
        phase = .open(id)
        return takeArrival()
    }

    public func isOpening(_ session: SessionID, generation: Int) -> Bool {
        phase == .opening(generation: generation, session: session)
    }

    public mutating func hide() {
        isShown = false
    }

    public mutating func close() -> SessionID? {
        end()
    }

    public mutating func keep() -> SessionID? {
        guard case .open = phase else { return nil }
        return end()
    }

    private mutating func end() -> SessionID? {
        let ending: SessionID? = switch phase {
        case .open(let id): id
        case .opening(_, let session): session
        case .idle: nil
        }
        generation += 1
        phase = .idle
        isShown = false
        pending = Arrival()
        return ending
    }

    private mutating func beginOpening(keeping: SessionID?) -> Opening {
        generation += 1
        phase = .opening(generation: generation, session: nil)
        return Opening(generation: generation, keeping: keeping)
    }

    private mutating func takeArrival() -> Arrival {
        defer { pending = Arrival() }
        return pending
    }
}

import Foundation
import Synchronization

public final class BridgeRegistry: Sendable {
    private struct State {
        var identities: [String: BridgeIdentity] = [:]
        var tokens: [SessionID: String] = [:]
        var ownerToken: String?
        var ownerSessions: Set<SessionID> = []
        var profilePins: [SessionID: ProfileID] = [:]
    }

    private let state = Mutex(State())
    private let makeToken: @Sendable () -> String

    public init(makeToken: @escaping @Sendable () -> String = BridgeRegistry.randomToken) {
        self.makeToken = makeToken
    }

    public static let randomToken: @Sendable () -> String = {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    public func mint(
        sessionID: SessionID,
        workspaceID: WorkspaceID,
        role: BridgeRole,
        launchedOrchestrating: Bool = false,
        launchedAsking: Bool = false
    ) -> String {
        let token = makeToken()
        state.withLock { state in
            if let previous = state.tokens[sessionID] { state.identities[previous] = nil }
            state.tokens[sessionID] = token
            state.identities[token] = BridgeIdentity(
                sessionID: sessionID,
                workspaceID: workspaceID,
                role: role,
                launchedOrchestrating: launchedOrchestrating,
                launchedAsking: launchedAsking
            )
        }
        return token
    }

    public func admit(ownerToken token: String) {
        state.withLock { state in
            if let previous = state.ownerToken, previous != token {
                state.identities[previous] = nil
                for sessionID in state.ownerSessions {
                    if let minted = state.tokens.removeValue(forKey: sessionID) {
                        state.identities[minted] = nil
                    }
                }
            }
            state.ownerToken = token
            state.identities[token] = .owner
        }
    }

    @discardableResult
    public func mintOwner(sessionID: SessionID) -> String {
        let token = makeToken()
        state.withLock { state in
            if let previous = state.tokens[sessionID] { state.identities[previous] = nil }
            state.tokens[sessionID] = token
            state.ownerSessions.insert(sessionID)
            state.identities[token] = BridgeIdentity(ownerSession: sessionID)
        }
        return token
    }

    public func identity(forToken token: String) -> BridgeIdentity? {
        state.withLock { state in
            guard let identity = state.identities[token] else { return nil }
            guard identity.role == .owner, let sessionID = identity.sessionID,
                  let pin = state.profilePins[sessionID] else { return identity }
            return BridgeIdentity(ownerSession: sessionID, pinnedProfile: pin)
        }
    }

    public func pinProfile(_ profile: ProfileID, forSession sessionID: SessionID) {
        state.withLock { state in
            if state.profilePins[sessionID] == nil { state.profilePins[sessionID] = profile }
        }
    }

    public func releaseProfilePin(forSession sessionID: SessionID) {
        state.withLock { _ = $0.profilePins.removeValue(forKey: sessionID) }
    }

    public func retire(sessionID: SessionID) {
        state.withLock { state in
            if let token = state.tokens.removeValue(forKey: sessionID) { state.identities[token] = nil }
            state.ownerSessions.remove(sessionID)
            state.profilePins[sessionID] = nil
        }
    }

    public var liveSessions: Set<SessionID> {
        state.withLock { Set($0.tokens.keys).union($0.ownerSessions) }
    }

    public var count: Int {
        state.withLock { $0.identities.count }
    }
}

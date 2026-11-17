import Foundation

public enum AgentSessionRecord {
    public static func write(
        _ settlement: AgentSessionSettlement,
        session: SessionID,
        account: AgentAccountHome?,
        standings: [AgentAccountStanding],
        in store: Store
    ) async throws {
        guard !settlement.changesNothing else { return }
        try await AgentAccountAssignment.remember(account, in: store)
        if let target = settlement.switchTarget {
            try await store.switchSegment(sessionID: session, to: target.named(
                account.map { AgentAccountNames.spoken(of: $0, among: standings) }
            ))
            return
        }
        if let recorded = settlement.recordedAccount {
            try await store.update(sessionID: session, accountID: recorded)
        }
    }
}

import Foundation
import Core

extension AppModel {
    var shownQuotas: QuotaShown {
        var shown = QuotaShown.make(
            stored: storedQuotas, readings: quotaReadings, scope: quotaScope, reading: quotaLedger.inFlight
        )
        shown.unanswered.formUnion(seededQuotaSilence.silent)
        shown.withoutLimits.formUnion(seededQuotaSilence.declining)
        return shown
    }

    var quotas: [AgentQuota] { shownQuotas.quotas }

    var accounts: [AgentKind: AgentAccount] { shownQuotas.accounts }

    var unansweredQuotaProviders: Set<AgentKind> { shownQuotas.unanswered }

    var quotalessProviders: Set<AgentKind> { shownQuotas.withoutLimits }

    var lastReportedQuotas: [AgentKind: Date] { shownQuotas.lastReported }

    func recordQuotas(_ reported: [AgentQuota], heldBy holder: QuotaHolder) async {
        await recordQuotas(reported.map { $0.held(by: holder) })
    }
}

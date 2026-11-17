import SwiftUI
import Core

#if DEBUG
@MainActor
extension AgentAccountProbe {
    private static let compactNow = Date(timeIntervalSince1970: 1_794_441_600)

    private static func compactQuota(
        _ provider: AgentKind,
        _ window: QuotaWindow,
        _ fraction: Double,
        resetsIn seconds: TimeInterval
    ) -> AgentQuota {
        AgentQuota(
            provider: provider,
            window: window,
            measure: .fraction(fraction),
            resetsAt: compactNow.addingTimeInterval(seconds),
            observedAt: compactNow
        )
    }

    private static func claudeModel(_ name: String, _ fraction: Double) -> AgentQuota {
        compactQuota(
            .claudeCode,
            QuotaWindow(key: "seven_day_model_\(name.lowercased())", label: "Week (\(name))", duration: 604_800),
            fraction,
            resetsIn: 6 * 86_400 + 82_800
        )
    }

    private static func compactQuotas(claudeModels: [(String, Double)]) -> [AgentQuota] {
        let week: TimeInterval = 604_800
        return [
            compactQuota(.claudeCode, .lasting(week, key: "seven_day"), 0.03, resetsIn: 6 * 86_400 + 82_800),
            compactQuota(.codex, .lasting(2_592_000, key: "primary"), 0.11, resetsIn: 19 * 86_400 + 46_800),
            compactQuota(.grok, .lasting(week, key: "weekly"), 0.53, resetsIn: 3 * 86_400 + 50_400),
            compactQuota(
                .antigravity, QuotaWindow(key: "gemini-weekly", label: "Gemini", duration: week), 0.04,
                resetsIn: 6 * 86_400 + 74_220
            ),
            compactQuota(
                .antigravity, QuotaWindow(key: "3p-weekly", label: "Claude", duration: week), 0,
                resetsIn: 6 * 86_400 + 85_200
            ),
        ] + claudeModels.map { claudeModel($0.0, $0.1) }
    }

    private static func compactScene(_ name: String, claudeModels: [(String, Double)], expanded: Bool) -> Scene {
        let accounts: [AgentKind: AgentAccount] = [
            .claudeCode: AgentAccount(provider: .claudeCode, plan: "Ultra", observedAt: compactNow),
            .codex: AgentAccount(
                provider: .codex,
                plan: "Free",
                credits: AgentAccount.Credits(balance: 0, isUnlimited: false),
                resetCredits: AgentAccount.ResetCredits(available: 1, expiries: []),
                observedAt: compactNow
            ),
            .grok: AgentAccount(provider: .grok, plan: "SuperGrok Lite", observedAt: compactNow),
        ]
        let workspace = Workspace(
            repoID: RepoID("repo"),
            name: "fix: testes inst\u{E1}veis #457 e #412",
            branch: "fix/457",
            path: "/tmp/fix",
            baseBranch: "develop"
        )
        let content = MenuBarPanelContent.make(MenuBarPanelContent.Input(
            workspaces: [workspace],
            running: [workspace.id],
            waiting: [],
            agentsByWorkspace: [workspace.id: 1],
            quotas: compactQuotas(claudeModels: claudeModels),
            accounts: accounts,
            unanswered: [],
            withoutLimits: [],
            lastReported: [:],
            layout: UsageLayout(
                expandedProviders: expanded ? [.claudeCode] : []
            ),
            hold: .whileAgentsRun,
            now: compactNow
        ))
        let height: CGFloat = expanded ? 760 : 680
        return Scene(
            name: "compact-\(name)",
            size: CGSize(width: MenuBarPanelPlacement.width, height: height),
            view: AnyView(
                VStack(spacing: MenuBarModuleStyle.gap) {
                    MenuBarKeepAwakeChip(hold: .whileAgentsRun, now: compactNow, showsOptions: .constant(false), openSettings: {})
                    MenuBarStatusModule(content: content, openSettings: {})
                    ForEach(content.providers) { provider in
                        MenuBarProviderModule(
                            provider: provider,
                            plan: accounts[provider.kind]?.plan,
                            options: UsageDisplayOptions(),
                            now: compactNow,
                            retry: {},
                            toggleFold: {}
                        )
                    }
                    MenuBarAgentsModule(agents: content.agents, more: content.moreAgents, open: { _ in }, openRunning: {})
                    MenuBarFooterModule(openSettings: {}, quit: {})
                }
                .padding(MenuBarModuleStyle.edge)
                .frame(width: MenuBarPanelPlacement.width, height: height, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
            )
        )
    }

    static func compactPanelScenes() -> [Scene] {
        let eight = [("Opus", 0.62), ("Sonnet", 0.48), ("Haiku", 0.12), ("Fable", 0.0), ("Opus 1M", 0.05), ("Sonnet 1M", 0.02)]
        return [
            compactScene("today", claudeModels: [("Fable", 0.0)], expanded: false),
            compactScene("eight-folded", claudeModels: eight, expanded: false),
            compactScene("eight-expanded", claudeModels: eight, expanded: true),
        ]
    }
}
#endif

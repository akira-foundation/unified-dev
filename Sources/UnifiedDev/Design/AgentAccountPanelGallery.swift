import SwiftUI
import Core

#if DEBUG
@MainActor
extension AgentAccountProbe {
    private static let width: CGFloat = 680

    private static func home(_ name: String, _ provider: AgentKind, isDefault: Bool = false) -> AgentAccountHome {
        AgentAccountHome(
            provider: provider,
            id: isDefault ? AgentAccountHome.defaultID(for: provider) : AgentAccountID(name),
            directory: URL(filePath: "/Users/ada/accounts/\(provider.rawValue)/\(name)", directoryHint: .isDirectory),
            isDefault: isDefault
        )
    }

    private static func standing(
        _ home: AgentAccountHome,
        email: String? = nil,
        plan: String? = nil,
        expires: Date? = nil,
        report: AgentAccountLiveness.CliReport = .unanswered,
        exists: Bool = true,
        doubt: String? = nil
    ) -> AgentAccountStanding {
        AgentAccountStanding(
            home: home,
            identity: AgentAccountIdentity(email: email, plan: plan, expiresAt: expires),
            cliReport: report,
            isolationDoubt: doubt,
            directoryExists: exists
        )
    }

    private static let expiry = Date(timeIntervalSince1970: 1_793_000_000)

    private static var claudeDefault: AgentAccountStanding {
        standing(home("default", .claudeCode, isDefault: true), email: "ada@home.example", plan: "Max 5x", expires: expiry, report: .claimsSession)
    }

    private static var claudeAccounts: [AgentAccountStanding] {
        [
            standing(home("client", .claudeCode), email: "ada@client.example", plan: "Team", expires: expiry, report: .claimsSession),
            standing(home("lab", .claudeCode), email: "ada@lab.example", plan: "Pro", report: .unanswered),
            standing(home("old", .claudeCode), report: .claimsNoSession),
        ]
    }

    private static func pane(
        _ name: String,
        _ provider: AgentKind,
        _ standings: [AgentAccountStanding],
        codex: CodexAuthStorageMode = .file,
        activity: AgentAccountsModel.Activity = .idle,
        orphans: [AgentAccountHome] = [],
        refusing refused: AgentAccountID? = nil,
        height: CGFloat
    ) -> Scene {
        let panel = AgentAccountPanel.make(provider: provider, standings: standings, orphans: orphans, codexStorageMode: codex)
        let notice = panel.rows.first { $0.id == refused }.map {
            AgentAccountRemovalNotice.after(
                AgentAccountError.folderInUse($0.home.directory.path), removing: $0
            )
        }
        return Scene(
            name: "pane-\(name)",
            size: CGSize(width: width, height: height),
            view: AnyView(
                Form {
                    AgentAccountsSection(
                        panel: panel, activity: activity, removalNotice: notice, canSignIn: true,
                        onAdd: {}, onRemove: { _ in }, onSignInAgain: { _ in }
                    )
                }
                .settingsForm()
            )
        )
    }

    static func panelScenes() -> [Scene] {
        let defaultOnly = [claudeDefault]
        let one = [claudeDefault] + claudeAccounts.prefix(1)
        let three = [claudeDefault] + claudeAccounts
        let codexDefault = standing(
            home("default", .codex, isDefault: true), email: "ada@home.example", plan: "Pro 20x", expires: expiry,
            report: .claimsSession,
            doubt: "Codex keeps its login in the system keychain here, which a separate directory does not keep apart."
        )
        let codexLab = standing(
            home("lab", .codex), email: "ada@lab.example", plan: "Plus", report: .unanswered,
            doubt: "Codex keeps its login in the system keychain here, which a separate directory does not keep apart."
        )
        let gone = standing(home("gone", .claudeCode), exists: false)
        let labelled = AgentAccountStanding(
            home: AgentAccountHome(
                provider: .claudeCode, id: AgentAccountID("studio"),
                directory: URL(filePath: "/Users/ada/accounts/claudeCode/studio", directoryHint: .isDirectory),
                isDefault: false, label: "Studio"
            ),
            identity: AgentAccountIdentity(), cliReport: .claimsNoSession, isolationDoubt: nil
        )
        return [
            pane("zero", .claudeCode, defaultOnly, height: 420),
            pane("one", .claudeCode, one, height: 700),
            pane("three", .claudeCode, three, height: 1_160),
            pane("refused", .claudeCode, three, refusing: AgentAccountID("old"), height: 1_260),
            pane("refused-unfinished", .claudeCode, [claudeDefault], orphans: [home("client", .claudeCode)], refusing: AgentAccountID("client"), height: 900),
            pane("checking", .claudeCode, defaultOnly, activity: .checkingSessions, height: 420),
            pane("unfinished", .claudeCode, [claudeDefault, labelled], orphans: [home("client", .claudeCode)], height: 1_000),
            pane("folder-missing", .claudeCode, defaultOnly + [gone], height: 800),
            pane("codex-keyring", .codex, [codexDefault, codexLab], codex: .keyring, height: 900),
            pane("grok", .grok, [standing(home("default", .grok, isDefault: true))], height: 420),
            pane("cursor", .cursor, [], height: 160),
            Scene(
                name: "preset-editor",
                size: CGSize(width: 480, height: 300),
                view: AnyView(ModelPresetEditor(
                    draft: ModelPresetDraft(preset: ModelPreset(
                        name: "Opus 5 High", model: "opus", effort: "high", backend: .claudeCode, permissionMode: .auto
                    )),
                    onSave: { _ in },
                    onCancel: {}
                ))
            ),
        ]
    }
}
#endif

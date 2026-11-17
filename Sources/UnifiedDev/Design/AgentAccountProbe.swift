import AppKit
import Core
import SwiftUI

#if DEBUG
@MainActor
enum AgentAccountProbe {
    private static let flag = "--agent-account-probe"

    static var isRequested: Bool { CommandLine.arguments.contains(flag) }

    static func runAndExit() -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { await run() }
        RunLoop.main.run()
        exit(1)
    }

    private static var directory: String {
        ProbeHarness.text(flag, or: NSTemporaryDirectory() + "unifieddev-agent-account")
    }

    private static func run() async {
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("\(directory): \(error)\n".utf8))
            exit(1)
        }
        var written = 0
        var wanted = 0
        for scene in scenes() {
            for scheme in [ColorScheme.light, .dark] {
                wanted += 1
                if await shoot(scene, scheme: scheme) { written += 1 }
            }
        }
        FileHandle.standardError.write(Data("wrote \(written) of \(wanted)\n".utf8))
        exit(written == wanted ? 0 : 1)
    }

    struct Scene {
        var name: String
        var size: CGSize
        var view: AnyView
    }

    private static func home(_ name: String, _ provider: AgentKind, isDefault: Bool = false) -> AgentAccountHome {
        AgentAccountHome(
            provider: provider,
            id: isDefault ? AgentAccountHome.defaultID(for: provider) : AgentAccountID(name),
            directory: URL(filePath: "/Users/ada/accounts/\(provider.rawValue)/\(name)", directoryHint: .isDirectory),
            isDefault: isDefault
        )
    }

    private static var standings: [AgentAccountStanding] {
        func standing(_ home: AgentAccountHome, email: String?, doubt: String? = nil) -> AgentAccountStanding {
            AgentAccountStanding(
                home: home, identity: AgentAccountIdentity(email: email),
                cliReport: .unanswered, isolationDoubt: doubt
            )
        }
        return [
            standing(home("default", .claudeCode, isDefault: true), email: "ada@home.example"),
            standing(home("work", .claudeCode), email: "ada@client.example"),
            standing(home("default", .codex, isDefault: true), email: nil),
            standing(
                home("lab", .codex), email: "ada@lab.example",
                doubt: "Codex keeps its login in the system keychain here, which a separate directory does not keep apart."
            ),
        ]
    }

    private static func options(
        _ scope: AgentAccountOptions.Scope = .project,
        stored: [AgentKind: String] = [:],
        inherited: [AgentKind: String] = [:],
        outsideProfile: Bool = false
    ) -> AgentAccountOptions {
        let own = stored.mapValues(AgentAccountID.init)
        let choices = scope == .profile
            ? AgentAccountChoices(profile: own)
            : AgentAccountChoices(project: own, profile: inherited.mapValues(AgentAccountID.init))
        return AgentAccountOptions.make(
            scope: scope, choices: choices, standings: standings, outsideProfile: outsideProfile
        )
    }

    static var profileOptions: AgentAccountOptions {
        options(.profile, stored: [.claudeCode: "work"], outsideProfile: true)
    }

    private static func form(_ options: AgentAccountOptions, failure: String? = nil) -> AnyView {
        AnyView(
            Form { AgentAccountRows(options: options, failure: failure, onPick: { _, _ in }, onAddAccount: {}) }
                .settingsForm()
                .scrollDisabled(true)
        )
    }

    private static func composer(project: String?, _ provider: AgentKind = .claudeCode) -> AnyView {
        let choice = AgentAccountChoice.resolve(
            provider: provider, project: project.map(AgentAccountID.init), standings: standings
        )
        let section = ComposerAccountSection.make(
            repoID: RepoID("preview"), provider: provider, choice: choice, standings: standings
        )
        return AnyView(
            VStack(alignment: .leading, spacing: Metrics.gutter) {
                HStack(spacing: Metrics.spacing) {
                    ComposerSettingsLabel(
                        text: "Opus 5 \u{b7} High", isActive: false, isOneOff: false, warns: section?.warns == true
                    )
                    Spacer()
                }
                .padding(Metrics.spacing)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: Metrics.cornerSmall))
                ComposerSettingsPanel(
                    controls: ComposerControls(agentKind: provider),
                    models: [],
                    efforts: [],
                    outputStyles: [],
                    permissionModes: [],
                    account: section,
                    suggestedPresetName: "",
                    onModel: { _ in },
                    onEffort: { _ in },
                    onOutputStyle: { _ in },
                    onPermissionMode: { _ in },
                    onContextWindow: { _ in },
                    onSavePreset: { _ in }
                )
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: Metrics.cornerSmall))
            }
            .padding(Metrics.gutter)
        )
    }

    private static func scenes() -> [Scene] {
        let form = CGSize(width: 620, height: 300)
        let tall = CGSize(width: 620, height: 340)
        let panel = CGSize(width: 360, height: 420)
        return [
            Scene(name: "profile-none", size: form, view: Self.form(options(.profile))),
            Scene(name: "profile-own-none", size: form, view: Self.form(options(.profile, outsideProfile: true))),
            Scene(name: "profile-one", size: form, view: Self.form(options(.profile, stored: [.claudeCode: "work"]))),
            Scene(name: "profile-unavailable", size: form, view: Self.form(options(.profile, stored: [.claudeCode: "deleted"]))),
            Scene(name: "project-follows-profile", size: tall, view: Self.form(options(inherited: [.claudeCode: "work"]))),
            Scene(name: "project-none", size: form, view: Self.form(options())),
            Scene(name: "project-default-only", size: form, view: Self.form(AgentAccountOptions.make(
                choices: .none, standings: standings.filter(\.home.isDefault)
            ))),
            Scene(name: "project-one", size: form, view: Self.form(options(stored: [.claudeCode: "work"]))),
            Scene(name: "project-two", size: tall, view: Self.form(options(stored: [.claudeCode: "work", .codex: "lab"]))),
            Scene(name: "project-doubt", size: tall, view: Self.form(options(stored: [.codex: "lab"]))),
            Scene(name: "project-unavailable", size: tall, view: Self.form(options(stored: [.claudeCode: "deleted"]))),
            Scene(name: "project-failure", size: form, view: Self.form(options(), failure: "Could not save the account: database is locked")),
            Scene(name: "composer-default", size: panel, view: Self.composer(project: nil)),
            Scene(name: "composer-project", size: panel, view: Self.composer(project: "work")),
            Scene(name: "composer-lost", size: panel, view: Self.composer(project: "deleted")),
            Scene(name: "composer-other-agent", size: panel, view: Self.composer(project: "lab", .codex)),
            Scene(name: "composer-no-accounts-lost", size: panel, view: Self.composer(project: "deleted", .cursor)),
        ] + panelScenes() + offerScenes() + grokUsageScenes() + compactPanelScenes()
    }

    private static func shoot(_ scene: Scene, scheme: ColorScheme) async -> Bool {
        guard let drawn = await OffscreenSnapshot.png(
            of: scene.view, size: scene.size, scheme: scheme, background: Palette.surface
        ) else { return false }
        let name = "\(scene.name)-\(scheme)"
        do {
            try drawn.write(to: URL(filePath: directory + "/" + name + ".png"))
            return true
        } catch {
            FileHandle.standardError.write(Data("\(name): \(error)\n".utf8))
            return false
        }
    }
}
#endif

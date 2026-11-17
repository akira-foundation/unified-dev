import SwiftUI
import Core

struct ChatSegmentsGallery: View {
    var app: AppModel

    private let sections = [
        ComposerModelSection(kind: .claudeCode, options: ComposerOption.models),
        ComposerModelSection(kind: .codex, options: [ComposerOption(id: "gpt-5.6-sol", label: "GPT-5.6 Sol")]),
        ComposerModelSection(kind: .grok, options: [ComposerOption(id: "grok-4", label: "Grok 4")]),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.pane) {
            VStack(alignment: .leading, spacing: Metrics.pane) {
                captioned("A chat that has spoken: Model, then New chat") { panel(.claudeCode, opens: true) }
                captioned("A chat that has not spoken: no New chat row") { panel(.codex, opens: false) }
            }
            VStack(alignment: .leading, spacing: Metrics.pane) {
                captioned("The divider a switch leaves, and the line a resume leaves") {
                    VStack(alignment: .leading, spacing: Metrics.pane) {
                        Text("I wrote src/lamp.txt. The next step is checking the wick.")
                            .font(Typo.body)
                        HandoffDividerView(mark: .continued(agent: .codex, model: "gpt-5.6-sol", from: .claudeCode))
                        HandoffDividerView(mark: .resuming)
                        Text("I read what Claude Code did, and src/lamp.txt is there.")
                            .font(Typo.body)
                        HandoffDividerView(mark: .continued(agent: .claudeCode, model: "opus", from: .codex))
                        HandoffDividerView(mark: .continued(
                            agent: .claudeCode, model: "opus", from: .claudeCode, account: "ada@client.example"
                        ))
                    }
                    .frame(width: 560, alignment: .leading)
                }
            }
        }
        .padding(Metrics.pane)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface)
        .environment(app)
    }

    private static func ignoring(_ kind: AgentKind) {}

    private func panel(_ kind: AgentKind, opens: Bool) -> some View {
        let modes: [ComposerOption] = ComposerControls(agentKind: kind).permissionModeChoices.map {
            ComposerOption(id: $0.mode.rawValue, label: $0.label, detail: $0.summary)
        }
        let opener: (@MainActor (AgentKind) -> Void)? = opens ? Self.ignoring : nil
        let controls = ComposerControls(model: kind == .codex ? "gpt-5.6-sol" : "opus", agentKind: kind)
        return ComposerSettingsPanel(
            controls: controls,
            models: sections,
            efforts: ComposerModelCatalog.shared.efforts(
                for: controls.agentKind, model: controls.model, offeringAgentDefault: true
            ),
            outputStyles: [],
            permissionModes: modes,
            matchedPreset: nil,
            suggestedPresetName: "",
            onModel: { _ in },
            onEffort: { _ in },
            onOutputStyle: { _ in },
            onPermissionMode: { _ in },
            onContextWindow: { _ in },
            onOpenInNewChat: opener,
            onSavePreset: { _ in }
        )
        .background(Palette.windowBackground)
    }

    private func captioned(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typo.caption)
                .foregroundStyle(Palette.textTertiary)
            content()
        }
    }
}

extension Gallery {
    static let chatSegments = Gallery(
        name: "chat-segments",
        title: "Chat segments",
        size: CGSize(width: 1000, height: 720),
        needsFocus: false,
        view: { app in AnyView(ChatSegmentsGallery(app: app)) }
    )
}

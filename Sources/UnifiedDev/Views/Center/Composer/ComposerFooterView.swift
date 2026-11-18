import SwiftUI
import Core

struct ComposerFooterView: View {
    var controls: ComposerControls
    var onChange: @MainActor (ComposerControls) -> Void
    var onOpenInNewChat: (@MainActor (ComposerControls) -> Void)?
    var context: ContextWindowUsage?
    var isRunning: Bool = false
    var queues: Bool = false
    var canSend: Bool
    var intent: ComposerIntent = .send
    var adaptsToWidth: Bool = true
    var project: String?
    var onAttach: @MainActor () -> Void
    var onQuickPrompt: (@MainActor (QuickPromptPanelRow) -> Void)?
    var projectQuickPrompts: [ProjectQuickPrompt] = []
    var onOpenQuickPrompts: (@MainActor () -> Void)?
    var onSend: @MainActor () -> Void
    var onStop: @MainActor () -> Void = {}
    var onSideConversation: (@MainActor () -> Void)?
    var showsAgentControls: Bool = true
    var orchestrates: Bool = false
    var usesCLIChat: Binding<Bool>?
    var supportsCLIChat: Bool = true
    var account: ComposerAccountSection?
    var accountHomes: ComposerAccountHomes?
    var settingsCloseRequests: ComposerSettingsCloseRequests

    @State private var loadedSpeed: CodexSpeed?
    @State private var loadedSpeedRequest: [String]?
    @State private var speedFailed = false

    private var speedRequest: [String] {
        [
            project ?? "", controls.agentKind.rawValue, controls.model, String(showsAgentControls),
            accountHomes?.codex?.directory.path ?? "",
            String(accountHomes != nil),
            String(accountHomes?.refused.contains(.codex) ?? false),
        ]
    }

    private var codexSpeed: CodexSpeed? {
        loadedSpeedRequest == speedRequest ? loadedSpeed : nil
    }

    @State private var extraModels: [String] = []
    @State private var extraEfforts: [String] = []

    @State private var outputStyles = ComposerOutputStyleCatalog()

    private var catalog: ComposerModelCatalog { ComposerModelCatalog.shared }

    @State private var isShowingContextDetail = false
    @State private var controlHeight: CGFloat?
    @State private var gaugeFrame: CGRect?

    var body: some View {
        let choices = self.choices

        return Group {
            if adaptsToWidth {
                ViewThatFits(in: .horizontal) {
                    row(isCompact: false, showsContext: true, choices: choices)
                    row(isCompact: true, showsContext: true, choices: choices)
                    row(isCompact: true, showsContext: false, choices: choices)
                }
            } else {
                row(isCompact: false, showsContext: true, choices: choices)
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .coordinateSpace(.named(composerFooterSpace))
        .popover(
            isPresented: $isShowingContextDetail,
            attachmentAnchor: gaugeFrame.map { .rect(.rect($0)) } ?? .rect(.bounds),
            arrowEdge: .top
        ) {
            if let context {
                ContextWindowDetail(usage: context)
                    .environment(\.fontScale, 1)
            }
        }
        .onChange(of: controls.model, initial: true) { _, id in
            remember(id, known: catalog.options(for: controls.agentKind), in: &extraModels)
        }
        .onChange(of: controls.effort, initial: true) { _, id in
            remember(id, known: efforts, in: &extraEfforts)
        }
        .task { if showsAgentControls { catalog.load() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if showsAgentControls { catalog.load() }
        }
        .task(id: speedRequest) {
            let request = speedRequest
            loadedSpeed = nil
            loadedSpeedRequest = request
            speedFailed = false
            guard showsAgentControls, controls.agentKind == .codex, let accountHomes,
                  !accountHomes.refused.contains(.codex)
            else { return }
            do {
                let speed = try await CodexSpeed.read(
                    cwd: project ?? AgentScratchDirectory.current(), modelID: controls.model, account: accountHomes.codex
                )
                guard !Task.isCancelled else { return }
                loadedSpeed = speed
            } catch {
                guard !Task.isCancelled else { return }
                speedFailed = true
            }
        }
        .task(id: OutputStyleKey(
            project: project, claude: accountHomes?.claude, known: accountHomes != nil,
            refused: accountHomes?.refused ?? []
        )) {
            guard showsAgentControls, let accountHomes else { return }
            let catalog = ComposerOutputStyleCatalog.shelves.catalogue(
                project: project, account: accountHomes.claude, refusing: accountHomes.refused
            )
            outputStyles = catalog
            await catalog.refreshIfStale(project: project)
        }
    }

    private func remember(_ id: String, known: [ComposerOption], in list: inout [String]) {
        guard !id.isEmpty, !known.contains(where: { $0.id == id }), !list.contains(id) else { return }
        list.append(id)
    }

    private struct Choices {
        var models: [ComposerModelSection] = []
        var efforts: [ComposerOption] = []
        var outputStyles: [ComposerOption] = []
        var permissionModes: [ComposerOption] = []
        var context: ContextWindowUsage.Reading?
    }

    private var choices: Choices {
        guard showsAgentControls else {
            return Choices(context: context?.reading)
        }
        return Choices(
            models: catalog.sections(includingCurrent: controls.model, on: controls.agentKind),
            efforts: ComposerOption.adding(extraEfforts, to: efforts),
            outputStyles: controls.offersOutputStyle
                ? outputStyles.options(includingCurrent: controls.outputStyle)
                : [],
            permissionModes: controls.permissionModeChoices(orchestrates: orchestrates).map {
                ComposerOption(id: $0.mode.rawValue, label: $0.label, detail: $0.summary)
            },
            context: context?.reading
        )
    }

    private func row(isCompact: Bool, showsContext: Bool, choices: Choices) -> some View {
        HStack(spacing: Metrics.spacing) {
            if showsAgentControls {
                ComposerSettingsPicker(
                    controls: controls,
                    models: choices.models,
                    catalogModels: catalog.models,
                    efforts: choices.efforts,
                    outputStyles: choices.outputStyles,
                    permissionModes: choices.permissionModes,
                    orchestrates: orchestrates,
                    isCompact: isCompact,
                    account: account,
                    onPreset: { preset in edit { $0 = $0.applying(preset, models: catalog.models) } },
                    onModel: selectModel,
                    onEffort: { id in edit { $0.effort = id } },
                    onOutputStyle: { id in edit { $0.outputStyle = id } },
                    onPermissionMode: selectPermissionMode,
                    onContextWindow: { tokens in edit { $0.codexContextWindow = tokens } },
                    onInteractionMode: { mode in edit { $0.interactionMode = mode } },
                    onOpenInNewChat: newChatOpener(offered: choices.models),
                    closeRequests: settingsCloseRequests
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlHeight = $0 }

                ComposerFastModeToggle(
                    controls: controls,
                    codexSpeed: codexSpeed,
                    codexSpeedFailed: loadedSpeedRequest == speedRequest && speedFailed,
                    height: controlHeight,
                    onChange: { value in edit { $0 = $0.settingFastMode(value) } }
                )
            }

            if intent == .send {
                Spacer(minLength: Metrics.spacing)
            }

            if let reading = choices.context, showsContext {
                ComposerContextGauge(
                    reading: reading, isShowingDetail: $isShowingContextDetail
                )
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(composerFooterSpace)) } action: {
                    gaugeFrame = $0
                }
            }

            ComposerToolGroup(
                showsAgentControls: showsAgentControls,
                onQuickPrompt: onQuickPrompt,
                projectQuickPrompts: projectQuickPrompts,
                onOpenQuickPrompts: onOpenQuickPrompts,
                onSideConversation: onSideConversation,
                onAttach: onAttach,
                usesCLIChat: usesCLIChat,
                supportsCLIChat: supportsCLIChat,
                height: controlHeight
            )

            if intent != .send {
                Spacer(minLength: Metrics.spacing)
            }

            if isRunning {
                ComposerStopButton(onStop: onStop)
            }

            ComposerSendButton(
                intent: intent,
                queues: queues,
                canSend: canSend,
                onSend: onSend
            )
        }
    }

    private func edit(_ change: (inout ComposerControls) -> Void) {
        var changed = controls
        change(&changed)
        guard changed != controls else { return }
        onChange(changed)
    }

    private func newChatOpener(offered sections: [ComposerModelSection]) -> (@MainActor (AgentKind) -> Void)? {
        guard let onOpenInNewChat else { return nil }
        return { kind in
            let offered = sections.first { $0.kind == kind }?.options.first?.id
            guard let opening = BackendChange.newChatControls(
                from: controls, on: kind, models: catalog.models, firstOffered: offered
            ) else { return }
            onOpenInNewChat(opening)
        }
    }

    private func selectPermissionMode(_ id: String) {
        guard let mode = PermissionMode(rawValue: id) else { return }
        edit { $0.permissionMode = mode }
    }

    private var efforts: [ComposerOption] {
        catalog.efforts(for: controls.agentKind, model: controls.model, offeringAgentDefault: true)
    }

    private func selectModel(_ tag: String) {
        let (backend, id) = catalog.choice(tag, current: controls.agentKind)
        edit {
            $0.model = id
            $0.agentKind = backend
            $0.effort = catalog.resolvedEffort($0.effort, for: backend, model: id)
        }
    }
}

private let composerFooterSpace = "composer.footer"

private struct OutputStyleKey: Equatable {
    var project: String?
    var claude: AgentAccountHome?
    var known: Bool
    var refused: Set<AgentKind>
}

import SwiftUI
import Core

struct UnifiedDevApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        #if DEBUG
        if SourceEditorProbe.isRequested { SourceEditorProbe.runAndExit() }
        if AppChromeProbe.isRequested { AppChromeProbe.runAndExit() }
        if BackgroundTaskProbe.isRequested { BackgroundTaskProbe.runAndExit() }
        if SideConversationProbe.isRequested { SideConversationProbe.runAndExit() }
        if ComposerInputProbe.isRequested { ComposerInputProbe.runAndExit() }
        if ComposerBusyProbe.isRequested { ComposerBusyProbe.runAndExit() }
        if MarkdownTableProbe.isRequested { MarkdownTableProbe.runAndExit() }
        if MarkdownSelectionProbe.isRequested { MarkdownSelectionProbe.runAndExit() }
        if MenuBarSpendProbe.isRequested { MenuBarSpendProbe.schedule() }
        if SpendScreenProbe.isRequested { SpendScreenProbe.runAndExit() }
        if AgentAccountProbe.isRequested { AgentAccountProbe.runAndExit() }
        if MergeConfirmationProbe.isRequested { MergeConfirmationProbe.runAndExit() }
        if OrchestratorSidebarProbe.isRequested { OrchestratorSidebarProbe.runAndExit() }
        if RepoOrchestratorProbe.isRequested { RepoOrchestratorProbe.runAndExit() }
        if UpdateAlertProbe.isRequested { UpdateAlertProbe.runAndExit() }
        if ArchiveRetentionProbe.isRequested { ArchiveRetentionProbe.runAndExit() }
        if ProfileProbe.isRequested { ProfileProbe.runAndExit() }
        if NotificationBellProbe.isRequested { NotificationBellProbe.runAndExit() }
        if ProfileToolbarProbe.isRequested { ProfileToolbarProbe.runAndExit() }
        if SearchPanelProbe.isRequested { SearchPanelProbe.runAndExit() }
        if CanvasEditorProbe.isRequested { CanvasEditorProbe.runAndExit() }
        #endif
        if BrowserViewportDemo.isRequested { BrowserViewportDemo.schedule() }
        CrashReportingService.shared.start()
        PreviewScenarioLaunch.prepare()

        AppearancePreference.apply(UserDefaults.standard.string(forKey: "appearance") ?? "system")

        if Snapshot.isRequested { Snapshot.runAndExit() }
        if Snapshot.isWindowCaptureRequested { Snapshot.scheduleWindowCapture() }
        if Snapshot.isGalleryCaptureRequested { Snapshot.scheduleGalleryCapture() }
        Snapshot.scheduleURLIfRequested()
        Snapshot.scheduleRunningStateIfRequested()
        Snapshot.scheduleSetupLogExpansionIfRequested()
        Snapshot.scheduleNoticeIfRequested()
        Snapshot.scheduleTerminalWorkspaceIfRequested()

        if FrameProbe.isRequested { FrameProbe.schedule() }

        if SwitchProbe.isRequested { SwitchProbe.schedule() }

        if TabProbe.isRequested { TabProbe.schedule() }

        if ScrollProbe.isRequested { ScrollProbe.schedule() }

        if ResizeProbe.isRequested { ResizeProbe.schedule() }
        if WindowResizeProbe.isRequested { WindowResizeProbe.schedule() }
        if DividerDragProbe.isRequested { DividerDragProbe.schedule() }

        if StreamProbe.isRequested { StreamProbe.schedule() }

        if JumpProbe.isRequested { JumpProbe.schedule() }

        if ComposerProbe.isRequested { ComposerProbe.schedule() }
        if TranscriptLayoutProbe.isRequested { TranscriptLayoutProbe.schedule() }
        if CommentFocusProbe.isRequested { CommentFocusProbe.schedule() }
        if MessageArrivalProbe.isRequested { MessageArrivalProbe.schedule() }
        if ArchiveFailureProbe.isRequested { ArchiveFailureProbe.schedule() }
        if ArchivedColumnsProbe.isRequested { ArchivedColumnsProbe.schedule() }
        if UnboundedHeightProbe.isRequested { UnboundedHeightProbe.schedule() }
        if ToolbarBandProbe.isRequested { ToolbarBandProbe.schedule() }
        if StreamingRenderingProbe.isRequested { StreamingRenderingProbe.schedule() }
        if MergeContrastProbe.isRequested { MergeContrastProbe.schedule() }
        if ReplyQuoteProbe.isRequested { ReplyQuoteProbe.schedule() }
        #if DEBUG
        if SelectionReplyProbe.isRequested { SelectionReplyProbe.schedule() }
        if StartingPointSuggestionProbe.isRequested { StartingPointSuggestionProbe.schedule() }
        #endif
        if WelcomeRestartProbe.isRequested { WelcomeRestartProbe.schedule() }

        if IdleProbe.isRequested { IdleProbe.schedule() }
        #if DEBUG
        if BusyProbe.isRequested { BusyProbe.schedule() }
        #endif
        if BrowserToolbarProbe.isRequested { BrowserToolbarProbe.schedule() }

        TranscriptStateDump.listen()

        #if DEBUG
        if MenuProbe.isRequested { MenuProbe.schedule() }
        if MenuActionProbe.isRequested { MenuActionProbe.schedule() }
        #endif
        Log.launchStep("app initialised")
    }

    static let widths = WindowWidths(
        sidebar: Self.sidebarMaximumWidth,
        sidebarMinimum: Self.sidebarMinimumWidth,
        detail: Metrics.centreColumnMinimum,
        inspector: Metrics.inspectorMinimum,
        divider: 1
    )

    static let mainWindowID = "main"

    static let sidebarMaximumWidth: CGFloat = 420

    static let sidebarMinimumWidth: CGFloat = 200

    var body: some Scene {
        Window(WindowTitleMark.decorate(WindowTitleMark.defaultTitle), id: Self.mainWindowID) {
            RootView()
                .environment(model)
                .frame(
                    minWidth: Self.widths.minimum(withInspector: model.isInspectorPresented),
                    minHeight: 620
                )
                .handlesAppURLs(using: model)
                .reportsAgentActivity(model)
                .runsBusyPulse(model)
                .showsWorkspaceInTitleBar(model)
                .showsAgentsInMenuBar(model)
                .onAppear { appDelegate.attach(model) }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1_440, height: 900)
        .commands {
            AppCommands(model: model)
        }

        Window("Settings", id: SettingsWindow.id) {
            SettingsView()
                .environment(model)
                .windowRole(.utility)
        }
        .defaultSize(width: 850, height: 700)
        .defaultPosition(.center)

        RepoSettingsWindow(model: model)

        OceansWindow(model: model)

        SpendScreenWindow(model: model)
    }
}

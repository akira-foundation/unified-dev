import SwiftUI
import Core

struct ChatPaneView: View {
    var transcript: TranscriptModel
    @Bindable var model: WorkspaceModel
    var pane: String

    @Environment(AppModel.self) private var app

    @State private var isTranscriptScrolledUp = false

    @State private var room = ComposerRoom()
    @State private var sideOrigin: SideConversation.Snapshot?

    @AppStorage(ChatTextSize.defaultsKey) private var textSize = ChatTextSize.defaultChoice
    @AppStorage(ChatFont.defaultsKey) private var chatFontID = ChatFont.standardID
    @AppStorage(ChatLineHeight.defaultsKey) private var lineHeight = ChatLineHeight.defaultChoice

    private var waiting: PaneWait? {
        transcript.isLoaded ? nil : .conversation(transcript.session.id)
    }

    var body: some View {
        TranscriptView(
            transcript: transcript,
            isRunningSetup: model.isRunningSetup,
            memory: TranscriptPaneMemory(model: model, pane: pane)
        ) { isTranscriptScrolledUp = $0 }
        .mask(alignment: .bottom) {
            VStack(spacing: 0) {
                Rectangle()
                Color.clear.frame(height: ComposerLayout.coverHeight)
            }
            .padding(.top, -SplitPaneFrame.underBarReach)
        }
        .environment(\.composerRoom, room)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            SlowLoadingView(subject: waiting, label: waiting?.label)
                .padding(.bottom, room.clearance)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            ComposerDock(
                showsJumpToNewest: isTranscriptScrolledUp,
                onJumpToNewest: transcript.jumpToLiveEnd
            ) {
                if transcript.home.workspaceID != nil {
                    BackgroundTasksPill(transcript: transcript) {
                        model.showTasks(of: transcript.session.id)
                        model.inspectorTab = .tasks
                        app.setInspectorVisible(true)
                    }
                }
                ComposerView(transcript: transcript, model: model, room: room)
            }
        }
        .overlay(alignment: .topLeading) {
            if let origin = sideOrigin, transcript.session.sideConversationParentID == nil {
                Button {
                    WorkspaceTabsStore.shared.reveal(.chat(origin.parentID), in: model)
                } label: {
                    Label("From \(origin.title)", systemImage: "arrow.turn.up.left")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(!model.sessions.contains { $0.id == origin.parentID })
                .padding(8)
            }
        }
        .task(id: transcript.session.id) {
            let origin = try? await model.store?.sideConversationSnapshot(sessionID: transcript.session.id)
            guard !Task.isCancelled else { return }
            sideOrigin = origin
        }
        .onGeometryChange(for: CGFloat.self) { PaneMeasure.room($0.size.height) } action: {
            room.height = $0
        }
        .environment(\.fontScale, textSize.scale)
        .environment(\.chatFont, ChatFont(rawValue: chatFontID))
        .environment(\.chatLineHeight, lineHeight)
    }
}

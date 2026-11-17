import SwiftUI
import Core

struct SideConversationView: View {
    var parent: TranscriptModel
    @Bindable var state: SideConversationState
    var model: WorkspaceModel
    @State private var room = ComposerRoom()

    var body: some View {
        SideConversationPanel(
            snapshot: state.snapshot,
            error: state.error,
            isBusy: state.isBusy,
            isOpen: state.transcript != nil,
            isKeeping: state.isKeeping,
            mainAgentIsRunning: parent.isRunning,
            onStartNew: { model.openSideConversation(from: parent, fresh: true) },
            onClose: { model.closeSideConversation(from: parent) },
            onKeep: { model.keepSideConversation(from: parent) },
            onRetry: { model.openSideConversation(from: parent) }
        ) {
            if let child = state.transcript { conversation(child) }
        }
        .focusedValue(\.composerTranscript, state.transcript)
        .onExitCommand { model.dismissSideConversation(from: parent) }
    }

    private func conversation(_ child: TranscriptModel) -> some View {
        TranscriptView(
            transcript: child,
            emptyState: TranscriptEmptyState(
                glyph: "arrow.turn.down.right", title: "What’s on your mind?",
                message: "Ask a follow-up about this work. The main conversation continues independently."
            )
        )
        .environment(\.composerRoom, room)
        .overlay(alignment: .bottom) {
            ComposerView(
                transcript: child, model: model, room: room,
                placeholder: "Ask a side question…",
                onDismiss: { model.dismissSideConversation(from: parent) },
                includesReviewComments: false
            )
        }
        .onGeometryChange(for: CGFloat.self) { PaneMeasure.room($0.size.height) } action: {
            room.height = $0
        }
        .id(child.session.id)
    }
}

struct SideConversationPanel<Conversation: View>: View {
    var snapshot: SideConversation.Snapshot?
    var error: String?
    var isBusy: Bool
    var isOpen: Bool
    var isKeeping: Bool
    var mainAgentIsRunning: Bool
    var onStartNew: () -> Void
    var onClose: () -> Void
    var onKeep: () -> Void
    var onRetry: () -> Void
    @ViewBuilder var conversation: Conversation

    var body: some View {
        VStack(spacing: 0) {
            header
            if let snapshot {
                Label {
                    Text("Recent context from \(snapshot.title) at \(snapshot.capturedAt.formatted(date: .omitted, time: .shortened))")
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: { Image(systemName: "arrow.triangle.branch") }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            Divider()
            if isOpen, let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(Palette.negative)
                    .textSelection(.enabled)
                    .padding(12)
            }
            if isOpen {
                conversation
            } else {
                ContentUnavailableView {
                    Label(
                        isBusy ? "Opening side conversation…" : "Could not open side conversation",
                        systemImage: "arrow.turn.down.right"
                    )
                } description: {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(error ?? "")
                            .textSelection(.enabled)
                    }
                } actions: {
                    if !isBusy { Button("Try Again", action: onRetry) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Side conversation")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Side conversation")
                .font(.headline)
            Spacer(minLength: 4)
            Menu {
                Button("Keep and Start New", action: onStartNew)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(isBusy || !isOpen)
            .help("Start a new side conversation with the latest context")
            .accessibilityLabel("Side conversation options")
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .disabled(isKeeping)
            .help("Close side conversation")
            .accessibilityLabel("Close side conversation")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Label(
                mainAgentIsRunning ? "Main agent working" : "Main agent idle",
                systemImage: mainAgentIsRunning ? "circle.dotted" : "checkmark.circle"
            )
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action: onKeep) {
                Label("Keep as Chat", systemImage: "arrow.up.right.square")
            }
            .controlSize(.small)
            .disabled(isBusy || !isOpen)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

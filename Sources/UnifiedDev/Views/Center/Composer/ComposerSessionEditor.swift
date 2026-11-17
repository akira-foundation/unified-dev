import Foundation
import Core

@MainActor
struct ComposerSessionEditor {
    var transcript: TranscriptModel
    var model: WorkspaceModel?

    func switchAgent(to controls: ComposerControls) {
        guard let switching = transcript.switchAgent(to: controls) else { return }
        mirror(transcript.session)
        Task {
            await switching.value
            mirror(transcript.session)
        }
    }

    private func mirror(_ session: Session) {
        if let model, let index = model.sessions.firstIndex(where: { $0.id == session.id }),
           model.sessions[index] != session {
            model.sessions[index] = session
        }
    }

    func apply(implementationMode: PermissionMode? = nil, _ change: (inout Session) -> Void) {
        guard !transcript.isWritingAgentSwitch else { return }
        var session = transcript.session
        change(&session)
        session.updatedAt = Date.now
        transcript.session = session
        mirror(session)
        Task {
            await transcript.updatePreferences(
                title: session.title,
                model: session.model,
                effort: session.effort,
                permissionMode: session.permissionMode,
                interactionMode: session.interactionMode,
                implementationMode: implementationMode,
                agentKind: session.agentKind
            )
        }
    }
}

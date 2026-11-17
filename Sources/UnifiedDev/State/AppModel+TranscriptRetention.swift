import Foundation
import Core

extension AppModel {
    static let transcriptReleaseDelay = Duration.seconds(2)

    func scheduleTranscriptRelease() {
        transcriptReleaseTask?.cancel()
        transcriptReleaseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.transcriptReleaseDelay)
            guard !Task.isCancelled else { return }
            self?.releaseIdleTranscripts()
        }
    }

    func releaseIdleTranscripts() {
        let models = Array(workspaceModels.values)
        let transcripts = models.flatMap(\.openTranscripts)
        let chats = transcripts.map(\.retention)
        let released = Set(TranscriptRetention.chatsToRelease(chats, selected: selection.workspaceID))
        for transcript in transcripts where released.contains(transcript.session.id) {
            transcript.releaseRows()
        }
        let idle = TranscriptRetention.workspacesToRelease(
            models.map(\.workspace.id), chats: chats, selected: selection.workspaceID
        )
        for id in idle { workspaceModels[id]?.releaseHeldFiles() }
    }
}

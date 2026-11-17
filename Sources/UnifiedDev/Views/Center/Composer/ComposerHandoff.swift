import SwiftUI
import Core

@MainActor
enum ComposerHandoff {
    struct Outcome: Sendable {
        var failure: String?
        var paths: [String] = []
    }

    @discardableResult
    static func attach(
        _ sources: [AttachmentSource],
        to model: WorkspaceModel,
        sessionID: SessionID? = nil,
        revealConversation: Bool = true,
        imageComment: BrowserImageComment? = nil,
        body: @escaping @Sendable ([String]) -> String = { $0.map(AttachmentDraft.token(for:)).joined(separator: " ") }
    ) async -> Outcome {
        let destination: Session? = if let sessionID {
            model.sessions.first { $0.id == sessionID }
        } else {
            model.activeSession
        }
        guard let session = destination else {
            return Outcome(failure: sessionID == nil
                ? "This workspace has no conversation to attach to yet."
                : "The conversation for this feedback has been closed.")
        }
        model.prepareTranscript(for: session.id)
        guard let transcript = model.existingTranscript(for: session.id) else {
            return Outcome(failure: "This workspace's conversation could not be opened.")
        }

        let key = session.id.rawValue
        let store = PromptAttachmentStore.shared
        store.load(sessionID: key)

        let added = await store.add(sources, sessionID: key, workspace: model.workspace.path)
        guard !added.paths.isEmpty else {
            return Outcome(failure: added.failures.first ?? "Nothing could be attached.")
        }

        if let imageComment { store.annotate(paths: added.paths, with: imageComment, sessionID: key) }
        append(body(added.paths), to: transcript)
        if revealConversation { WorkspaceTabsStore.shared.reveal(.chat(session.id), in: model) }

        return Outcome(failure: added.failures.first, paths: added.paths)
    }

    private static func append(_ addition: String, to transcript: TranscriptModel) {
        guard !addition.isEmpty else { return }
        let draft = transcript.draft
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            transcript.draft = addition + " "
            return
        }
        let separator = draft.hasSuffix("\n") ? "" : "\n"
        transcript.draft = draft + separator + addition + " "
    }
}

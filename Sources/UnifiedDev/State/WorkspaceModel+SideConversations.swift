import Core
import Foundation

extension WorkspaceModel {
    @discardableResult
    func openSideConversation(
        from parent: TranscriptModel, question: String = "", fresh: Bool = false, quoting: String = ""
    ) -> Bool {
        guard parent.session.sideConversationParentID == nil, store != nil else { return false }
        let parentID = parent.session.id
        let state = sideConversations[parentID] ?? SideConversationState()
        sideConversations[parentID] = state
        guard !state.isKeeping else { return false }
        showSideConversation(of: parent)
        switch state.lifecycle.start(question: question, quoting: quoting, fresh: fresh) {
        case .wait:
            return true
        case .resume(_, let arrival):
            guard let child = state.transcript else { return false }
            state.task = Task { await deliver(arrival, to: child, state: state) }
            return true
        case .open(let opening):
            begin(opening, from: parent, state: state)
            return true
        }
    }

    private func begin(
        _ opening: SideConversationLifecycle.Opening, from parent: TranscriptModel, state: SideConversationState
    ) {
        guard let store else { return }
        let parentID = parent.session.id
        let previous = state.transcript
        state.transcript = nil
        state.snapshot = nil
        state.error = nil
        let prior = state.task
        prior?.cancel()
        let closing = state.closing
        state.task = Task { [weak self] in
            await prior?.value
            await closing?.value
            guard let self else { return }
            if let kept = opening.keeping {
                do {
                    _ = try await store.keepSideConversation(sessionID: kept)
                    await reloadSessions()
                } catch {
                    guard let previous,
                          let arrival = state.lifecycle.keepFailed(generation: opening.generation, restoring: kept)
                    else { return }
                    state.transcript = previous
                    state.error = error.readableMessage
                    await deliver(arrival, to: previous, state: state)
                    return
                }
            }
            do {
                try Task.checkCancellation()
                let session = try await store.openSideConversation(
                    parentID: parentID, streamingText: parent.streamingText
                )
                guard state.lifecycle.opened(session.id, generation: opening.generation) else {
                    try await store.closeSideConversation(sessionID: session.id)
                    return
                }
                let snapshot = try await store.sideConversationSnapshot(sessionID: session.id)
                await reloadSessions()
                guard state.lifecycle.isOpening(session.id, generation: opening.generation) else { return }
                let child = transcript(for: session)
                state.transcript = child
                state.snapshot = snapshot
                await child.load()
                guard let arrival = state.lifecycle.ready(generation: opening.generation) else { return }
                if isShowingSideConversation(of: parent) { child.focusComposer() }
                await deliver(arrival, to: child, state: state)
            } catch {
                guard case .current(let arrived) = state.lifecycle.failed(generation: opening.generation) else { return }
                if let arrived { _ = try? await store.closeSideConversation(sessionID: arrived) }
                guard !(error is CancellationError) else { return }
                state.error = error.readableMessage
            }
        }
    }

    private func deliver(
        _ arrival: SideConversationLifecycle.Arrival, to child: TranscriptModel, state: SideConversationState
    ) async {
        arrival.quotes.forEach { child.reply(with: $0) }
        for question in arrival.questions {
            let stillOpen = state.lifecycle.sessionID == child.session.id
            guard stillOpen || child.session.sideConversationParentID == nil else { return }
            await child.submit(question)
        }
    }

    func dismissSideConversation(from parent: TranscriptModel) {
        leaveSideConversation(of: parent)
        sideConversations[parent.session.id]?.lifecycle.hide()
        parent.focusComposer()
    }

    func closeSideConversation(from parent: TranscriptModel) {
        guard let state = sideConversations[parent.session.id], !state.isKeeping else { return }
        state.task?.cancel()
        state.task = nil
        leaveSideConversation(of: parent)
        let ending = state.lifecycle.close()
        state.transcript = nil
        state.snapshot = nil
        state.error = nil
        parent.focusComposer()
        guard let ending else { return }
        state.closing = endSideConversation(ending)
    }

    func keepSideConversation(from parent: TranscriptModel) {
        guard let state = sideConversations[parent.session.id], let child = state.transcript,
              !state.isKeeping, state.lifecycle.sessionID == child.session.id, let store else { return }
        state.isKeeping = true
        let delivering = state.task
        state.task = Task { [weak self] in
            defer { state.isKeeping = false; state.task = nil }
            guard let self else { return }
            await delivering?.value
            do {
                guard let kept = try await store.keepSideConversation(sessionID: child.session.id) else { return }
                child.session = kept
                leaveSideConversation(of: parent)
                _ = state.lifecycle.keep()
                state.transcript = nil
                state.snapshot = nil
                await reloadSessions()
                WorkspaceTabsStore.shared.reveal(.chat(kept.id), in: self)
            } catch {
                state.error = error.readableMessage
            }
        }
    }
}

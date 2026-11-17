import Foundation

extension ComposerControls {
    public static func carried(from session: Session, in store: Store) async throws -> ComposerControls {
        let fast = (try await store.setting(fastModeKey(sessionID: session.id))) == "1"
        let style = (try await store.setting(outputStyleKey(sessionID: session.id))) ?? ""
        let window = CodexContextWindow.normalised(
            try await store.setting(contextWindowKey(sessionID: session.id))
        )
        let codexFastMode = CodexSpeed.override(stored: try await store.setting(CodexSpeed.key(sessionID: session.id)))
        return ComposerControls(
            session: session, isFastMode: fast, outputStyle: style,
            codexContextWindow: window, codexFastMode: codexFastMode
        )
    }
}

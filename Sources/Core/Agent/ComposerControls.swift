import Foundation

public struct ComposerControls: Equatable, Sendable {
    public var model: String
    public var effort: String
    public var agentKind: AgentKind {
        didSet {
            permissionMode = permissionMode.nearest(on: agentKind)
            interactionMode = interactionMode.nearest(on: agentKind)
        }
    }
    public var permissionMode: PermissionMode {
        didSet { permissionMode = permissionMode.nearest(on: agentKind) }
    }
    public var interactionMode: InteractionMode
    public var offersInteractionMode: Bool { InteractionMode.supports(agentKind) }
    public var isFastMode: Bool
    public var codexFastMode: Bool?
    public var outputStyle: String
    public var codexContextWindow: Int
    public var hasWorktree: Bool

    public init(
        model: String = AppDefaults.fallbackModel,
        effort: String = AppDefaults.fallbackEffort,
        agentKind: AgentKind = .claudeCode,
        permissionMode: PermissionMode = AppDefaults.fallbackPermissionMode,
        isFastMode: Bool = false,
        outputStyle: String = OutputStyle.defaultName,
        codexContextWindow: Int = CodexContextWindow.modelDefault,
        hasWorktree: Bool = true,
        codexFastMode: Bool? = nil,
        interactionMode: InteractionMode = .build
    ) {
        self.model = model
        self.effort = effort
        self.agentKind = agentKind
        self.permissionMode = permissionMode.nearest(on: agentKind)
        self.isFastMode = isFastMode
        self.codexFastMode = codexFastMode
        self.outputStyle = outputStyle
        self.codexContextWindow = codexContextWindow
        self.hasWorktree = hasWorktree
        self.interactionMode = interactionMode.nearest(on: agentKind)
    }

    public init(
        session: Session,
        isFastMode: Bool,
        outputStyle: String,
        codexContextWindow: Int = CodexContextWindow.modelDefault,
        codexFastMode: Bool? = nil
    ) {
        self.init(
            model: session.model,
            effort: session.effort,
            agentKind: session.agentKind,
            permissionMode: session.permissionMode,
            isFastMode: isFastMode,
            outputStyle: outputStyle,
            codexContextWindow: codexContextWindow,
            hasWorktree: session.workspaceID != nil,
            codexFastMode: codexFastMode,
            interactionMode: session.interactionMode
        )
    }

    public var availablePermissionModes: [PermissionMode] {
        switch agentKind {
        case .codex: PermissionMode.allCases.filter { $0 != .plan }
        case .claudeCode, .grok, .antigravity, .cursor, .openCode: PermissionMode.allCases.filter { $0 != .autoReview }
        }
    }

    public var permissionModeChoices: [PermissionModeChoice] {
        availablePermissionModes.map { PermissionModeChoice(mode: $0, on: agentKind) }
    }

    public var permissionModeNote: String? {
        guard !hasWorktree else { return nil }
        return "This conversation has no worktree, so anything wider than "
            + "\(PermissionMode.auto.label(on: agentKind)) reaches the whole machine "
            + "rather than a copy of a project. Whatever you choose lasts until Unified Dev "
            + "next starts, and then it is back to that."
    }

    public var offersOutputStyle: Bool {
        agentKind.offersOutputStyle
    }

    public var offersContextWindow: Bool {
        agentKind == .codex
    }

    public init(
        defaults: ComposerDefaults,
        isFastMode: Bool,
        outputStyle: String,
        codexContextWindow: Int = CodexContextWindow.modelDefault,
        codexFastMode: Bool? = nil
    ) {
        self.init(
            model: defaults.model,
            effort: defaults.effort,
            agentKind: defaults.backend,
            permissionMode: defaults.permissionMode,
            isFastMode: isFastMode,
            outputStyle: outputStyle,
            codexContextWindow: codexContextWindow,
            codexFastMode: codexFastMode,
            interactionMode: defaults.interactionMode
        )
    }

    public static func resolved(
        repo: RepoSettings,
        app: AppDefaults,
        models: [AgentKind: [AgentModel]] = [:]
    ) -> ComposerControls {
        ComposerControls(
            defaults: ComposerDefaults.resolve(repo: repo, app: app, models: models),
            isFastMode: app.fastMode,
            outputStyle: app.outputStyle,
            codexContextWindow: app.codexContextWindow
        )
    }

    public static func fastModeKey(sessionID: SessionID) -> String {
        "session.\(sessionID).fastMode"
    }

    public static func outputStyleKey(sessionID: SessionID) -> String {
        "session.\(sessionID).outputStyle"
    }

    public static func contextWindowKey(sessionID: SessionID) -> String {
        "session.\(sessionID).codexContextWindow"
    }

    public static func defaultsAppliedKey(sessionID: SessionID) -> String {
        "session.\(sessionID).defaultsApplied"
    }

    public func store(sessionID: SessionID, in store: Store) async {
        try? await store.saveComposerControls(self, sessionID: sessionID)
    }

    func settings(sessionID: SessionID) -> [(String, String?)] {
        [
            (Self.fastModeKey(sessionID: sessionID), isFastMode ? "1" : nil),
            (CodexSpeed.key(sessionID: sessionID), codexFastMode.map { $0 ? "1" : "0" }),
            (Self.outputStyleKey(sessionID: sessionID), OutputStyle.isDefault(outputStyle) ? nil : outputStyle),
            (Self.contextWindowKey(sessionID: sessionID), CodexContextWindow.stored(codexContextWindow)),
            (Self.defaultsAppliedKey(sessionID: sessionID), "1"),
        ]
    }
}

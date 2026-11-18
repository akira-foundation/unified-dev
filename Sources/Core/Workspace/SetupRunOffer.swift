import Foundation

public struct SetupRunOffer: Sendable, Hashable {
    public let title: String

    public let isEnabled: Bool

    public struct Live: Sendable, Hashable {
        public let hasSetupScript: Bool
        public let hasRunSetup: Bool
        public let isRunning: Bool

        public init(hasSetupScript: Bool, hasRunSetup: Bool, isRunning: Bool) {
            self.hasSetupScript = hasSetupScript
            self.hasRunSetup = hasRunSetup
            self.isRunning = isRunning
        }
    }

    public static func offer(
        hasSetupScript: Bool,
        hasRunSetup: Bool,
        isRunning: Bool
    ) -> SetupRunOffer? {
        guard hasSetupScript else { return nil }
        return SetupRunOffer(
            title: hasRunSetup ? "Run Setup Again" : "Run Setup",
            isEnabled: !isRunning
        )
    }

    public static func offer(_ live: Live) -> SetupRunOffer? {
        offer(hasSetupScript: live.hasSetupScript, hasRunSetup: live.hasRunSetup, isRunning: live.isRunning)
    }

    public static func hasRunSetup(setupState: SetupState, log: String) -> Bool {
        setupState != .pending || !log.isEmpty
    }

    public static func menuOffer(
        for workspace: Workspace,
        presence: SetupScriptPresence,
        live: Live?
    ) -> SetupRunOffer? {
        if let live { return offer(live) }
        return offer(
            hasSetupScript: presence.hasSetupScript(workspace),
            hasRunSetup: hasRunSetup(setupState: workspace.setupState, log: workspace.setupLog),
            isRunning: false
        )
    }
}

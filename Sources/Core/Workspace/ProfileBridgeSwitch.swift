import Foundation

public enum ProfileBridgeSwitch {
    public static let settingTitle = "Connected to other profiles"

    public static let caveat = "With this on in two profiles, any workspace in one can list the other's "
        + "projects and their orchestrators and send those orchestrators a message, from a chat in Accept edits, where you approve each call. "
        + "A project's orchestrator can also read the other's chats and changes and write to any of its "
        + "workspaces. Your own chat and client reach any profile with this on. A message wakes an agent and "
        + "arrives marked as coming from outside. Nothing is started there unless you click to start it. "
        + "Text planted in something an agent reads could still carry one organisation's work into another."

    public static let saveFailure = "This could not be saved, so it is as it was."

    private static let storedOn = "on"

    static func key(profile: ProfileID) -> String {
        "profile.\(profile).reachableFromOtherProfiles"
    }

    public static func parse(_ stored: String?) -> Bool {
        stored == storedOn
    }

    public static func isOn(profile: ProfileID, in store: Store) async -> Bool {
        parse(try? await store.setting(key(profile: profile)))
    }

    public static func save(_ isOn: Bool, profile: ProfileID, to store: Store) async throws {
        try await store.setSetting(key(profile: profile), isOn ? storedOn : nil)
    }
}

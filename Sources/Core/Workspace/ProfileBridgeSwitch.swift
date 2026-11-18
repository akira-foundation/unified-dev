import Foundation

public enum ProfileBridgeSwitch {
    public static let settingTitle = "Reachable from other profiles"

    public static let caveat = "With this on, any workspace in another profile can list this profile's "
        + "projects and their orchestrators and send those orchestrators a message, from a chat in Accept edits, where you approve each call. "
        + "Another profile's project orchestrators can also read chats and changes here and write to any "
        + "workspace here. Your own chat and client reach this profile. With it off, nothing comes in, not even "
        + "a reply, and workspaces here can still write to the profiles that have it on, saying where they write from. A message wakes an agent and "
        + "arrives marked as coming from outside. Nothing is started here unless you click to start it. "
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

import Foundation

public struct PromptOverrides: @unchecked Sendable {
    public static let keyPrefix = "prompts."

    public static func key(for id: PromptID) -> String {
        keyPrefix + id.rawValue
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func stored(for id: PromptID) -> String? {
        defaults.string(forKey: Self.key(for: id))
    }

    public func set(_ text: String?, for id: PromptID) {
        let key = Self.key(for: id)
        if let text {
            defaults.set(text, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public func isCustomised(for id: PromptID) -> Bool {
        stored(for: id) != nil
    }

    public func template(for id: PromptID, forge: ForgeKind = .gitHub) -> String {
        let override = stored(for: id) ?? ""
        guard !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PromptRegistry.defaultTemplate(for: id, forge: forge)
        }
        return override
    }
}

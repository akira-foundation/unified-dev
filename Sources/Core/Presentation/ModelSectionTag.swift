import Foundation

public enum ModelSectionTag {
    public static func tag(
        _ id: String,
        in section: AgentKind,
        running: AgentKind,
        models: [AgentKind: [AgentModel]]
    ) -> String {
        guard DefaultBackend.kind(ofModel: id, running: running, models: models) != section else { return id }
        return "\(section.rawValue):\(id)"
    }

    public static func choice(
        _ tag: String,
        running: AgentKind,
        models: [AgentKind: [AgentModel]]
    ) -> (kind: AgentKind, model: String) {
        (
            DefaultBackend.kind(ofModel: tag, running: running, models: models),
            ModelIdentifier.resolve(tag, models: models).model
        )
    }
}

import Foundation

public struct PreviewScenarioModelPin: Sendable, Equatable {
    public var project: String
    public var model: String

    public init(project: String, model: String) {
        self.project = project
        self.model = model
    }

    public var kind: AgentKind? { ModelIdentifier.resolve(model).kind }
}

extension PreviewScenario {
    public static let projectSettingsFile = ".unifieddev/settings.toml"

    public var modelPins: [PreviewScenarioModelPin] {
        projects.compactMap { project in
            guard let text = project.files[Self.projectSettingsFile],
                  let model = (try? TOML.parse(text))?["models.default"]?.stringValue
            else { return nil }
            return PreviewScenarioModelPin(project: project.name, model: model)
        }
    }
}

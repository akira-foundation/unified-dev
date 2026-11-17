import Foundation

enum WorkspaceListBriefRow {
    static func row(_ workspace: Workspace, project: Repo?) -> JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string(workspace.id.rawValue),
            "name": .string(workspace.name),
            "state": .string(workspace.state.rawValue),
            "orchestrator": .bool(workspace.isOrchestrator),
        ]
        if let project {
            fields["project"] = .object(["id": .string(project.id.rawValue), "name": .string(project.name)])
        }
        return .object(fields)
    }
}

import Foundation

extension PreviewScenario {
    public struct SeededNotification: Sendable, Equatable, Codable {
        public var event: NotificationEvent
        public var project: String
        public var workspace: String
        public var chat: String?
        public var detail: String
        public var minutesAgo: Double
        public var read: Bool
        public var removed: Bool

        public init(
            event: NotificationEvent,
            project: String,
            workspace: String,
            chat: String? = nil,
            detail: String = "",
            minutesAgo: Double = 0,
            read: Bool = false,
            removed: Bool = false
        ) {
            self.event = event
            self.project = project
            self.workspace = workspace
            self.chat = chat
            self.detail = detail
            self.minutesAgo = minutesAgo
            self.read = read
            self.removed = removed
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            event = try container.decode(NotificationEvent.self, forKey: .event)
            project = try container.decode(String.self, forKey: .project)
            workspace = try container.decode(String.self, forKey: .workspace)
            chat = try container.decodeIfPresent(String.self, forKey: .chat)
            detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
            minutesAgo = try container.decodeIfPresent(Double.self, forKey: .minutesAgo) ?? 0
            read = try container.decodeIfPresent(Bool.self, forKey: .read) ?? false
            removed = try container.decodeIfPresent(Bool.self, forKey: .removed) ?? false
        }
    }

    var notificationProblems: [String] {
        notifications.flatMap { notification -> [String] in
            guard let project = projects.first(where: { $0.name == notification.project }) else {
                return ["notification names project \"\(notification.project)\", which the scenario does not declare"]
            }
            guard !notification.removed else { return [] }
            guard let workspace = project.workspaces.first(where: { $0.name == notification.workspace }) else {
                return ["notification names workspace \"\(notification.workspace)\", which \(project.name) does not declare"]
            }
            guard let chat = notification.chat, !workspace.chats.contains(where: { $0.title == chat }) else { return [] }
            return ["notification names chat \"\(chat)\", which \(workspace.name) does not declare"]
        }
    }
}

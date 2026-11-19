import Foundation

public struct DiscardAlert: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case destructive
        case cancel
    }

    public struct Action: Equatable, Sendable {
        public let label: String
        public let role: Role

        public var confirms: Bool { role == .destructive }

        public init(label: String, role: Role) {
            self.label = label
            self.role = role
        }
    }

    public let title: String
    public let message: String
    public let note: String?
    public let actions: [Action]

    public static let confirm = Action(label: "Discard", role: .destructive)
    public static let cancel = Action(label: "Cancel", role: .cancel)
    public static let dismiss = Action(label: "OK", role: .cancel)

    public var body: String {
        [message, note].compactMap { $0 }.joined(separator: "\n\n")
    }

    public var canConfirm: Bool {
        actions.contains { $0.confirms }
    }

    public var returnKey: Action? {
        actions.first { $0.confirms } ?? (actions.count == 1 ? actions.first : nil)
    }

    public static func hunk(_ hunk: DiffHunk, path: String, staged: HunkDiscard.Staged) -> DiscardAlert {
        let allowed = HunkDiscard.canConfirm(staged)
        return DiscardAlert(
            title: HunkDiscard.question(path: path, staged: staged),
            message: HunkDiscard.losses(of: hunk, staged: staged),
            note: allowed ? HunkDiscard.note(staged) : nil,
            actions: allowed ? [confirm, cancel] : [dismiss]
        )
    }

    public static func file(_ file: ChangedFile, base: String, hasDraft: Bool) -> DiscardAlert {
        DiscardAlert(
            title: FileBarControls.discardQuestion(path: file.path),
            message: FileDiscard.losses(of: file, base: base, hasDraft: hasDraft),
            note: nil,
            actions: [confirm, cancel]
        )
    }
}

import Foundation

public enum FileDiscard {
    public static func losses(of file: ChangedFile, base: String, hasDraft: Bool) -> String {
        let action = switch file.change {
        case .untracked: "This moves \(file.path), which git does not track, to the Trash"
        case .added, .copied: "This deletes \(file.path), which did not exist on \(base)"
        case .modified, .deleted, .renamed, .typechange: "This restores \(file.path) to the version on \(base)"
        }
        let lost = [
            file.additions > 0 ? Counted.of(file.additions, "added line") : nil,
            file.deletions > 0 ? Counted.of(file.deletions, "removed line") : nil,
            hasDraft ? "the unsaved edits open in it" : nil,
        ].compactMap { $0 }
        guard let last = lost.last else { return action + "." }
        let listed = lost.count == 1 ? last : lost.dropLast().joined(separator: ", ") + " and " + last
        return action + ", losing " + listed + "."
    }
}

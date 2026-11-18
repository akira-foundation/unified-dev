import Foundation

public enum HunkDiscard {
    public enum Staged: Equatable, Sendable {
        case clean
        case holdsTheHunk
        case holdsAnotherVersion
        case divergesFromTheWorktree
        case addsLinesThatAreNotUTF8
        case unreadable
    }

    public enum Availability: Equatable, Sendable {
        case hidden
        case enabled
        case disabled(String)
    }

    public static let gitlinkMode = "160000"

    public static let whitespaceIsHidden =
        "Turn off Ignore whitespace to discard a single hunk. The hunks shown are not the ones on disk"

    public static let stagedStays =
        "This file has staged changes that this does not touch. They stay in the index, so your "
            + "next commit still carries them, even where they cover these same lines. Unstage "
            + "them with git restore --staged if you do not want them."

    public static let stagedUnknown =
        "Unified Dev could not read what the index holds for this file. If anything is staged "
            + "here, this leaves it as it is, and your next commit still carries it."

    public static let unstageFirst =
        "Unstage the file with git restore --staged, or commit what is staged, and then discard the hunk."

    public static let indexRefuses =
        "This file has staged changes over these lines that do not match the working file, so git "
            + "refuses to discard this hunk and nothing would be written. " + unstageFirst

    public static let addsLinesThatAreNotUTF8 =
        "This hunk adds lines that are not UTF-8, so Unified Dev cannot check that they are still the "
            + "ones shown here."

    public static let discardTheWholeFile = "Discard the whole file to put it back the way git has it."

    public static let draftIsOpen =
        "Save or throw away your unsaved edits to this file before discarding a single hunk"

    public static func offers(_ file: ChangedFile, in diff: FileDiff? = nil) -> Bool {
        guard !file.isBinary else { return false }
        if let diff, diff.oldMode == gitlinkMode || diff.newMode == gitlinkMode { return false }
        switch file.change {
        case .modified, .renamed: return true
        case .added, .deleted, .untracked, .copied, .typechange: return false
        }
    }

    public static func availability(
        file: ChangedFile, in diff: FileDiff? = nil, ignoringWhitespace: Bool,
        blocker: String?, hasUnsavedEdits: Bool
    ) -> Availability {
        guard offers(file, in: diff) else { return .hidden }
        if let blocker { return .disabled(blocker) }
        if hasUnsavedEdits { return .disabled(draftIsOpen) }
        if ignoringWhitespace { return .disabled(whitespaceIsHidden) }
        return .enabled
    }

    public static func refusal(
        file: ChangedFile, in diff: FileDiff? = nil, ignoringWhitespace: Bool,
        blocker: String?, hasUnsavedEdits: Bool
    ) -> String? {
        switch availability(
            file: file, in: diff, ignoringWhitespace: ignoringWhitespace,
            blocker: blocker, hasUnsavedEdits: hasUnsavedEdits
        ) {
        case .enabled: nil
        case .hidden: HunkDiscardRefusal.notOffered.errorDescription
        case let .disabled(reason): reason
        }
    }

    public static func question(path: String, staged: Staged = .clean) -> String {
        switch staged {
        case .divergesFromTheWorktree: "This hunk in \(path) cannot be discarded yet"
        case .addsLinesThatAreNotUTF8: "This hunk in \(path) cannot be discarded"
        case .clean, .holdsTheHunk, .holdsAnotherVersion, .unreadable: "Discard this hunk in \(path)?"
        }
    }

    public static func canConfirm(_ staged: Staged) -> Bool {
        staged != .divergesFromTheWorktree && staged != .addsLinesThatAreNotUTF8
    }

    public static func losses(of hunk: DiffHunk, staged: Staged) -> String {
        if staged == .divergesFromTheWorktree { return indexRefuses }
        if staged == .addsLinesThatAreNotUTF8 { return addsLinesThatAreNotUTF8 + " " + discardTheWholeFile }
        let added = hunk.lines.filter { $0.kind == .addition }.count
        let removed = hunk.lines.filter { $0.kind == .deletion }.count
        let clauses = [
            removed > 0 ? "puts back \(Counted.of(removed, "removed line"))" : nil,
            added > 0 ? "takes out \(Counted.of(added, "added line"))" : nil,
        ].compactMap { $0 }
        let change = clauses.isEmpty ? "This undoes the change" : "This " + clauses.joined(separator: " and ")
        return change + ". The rest of the file is left as it is.\n\n"
            + notice(staged) + NoUndo.sentence
    }

    static func notice(_ staged: Staged) -> String {
        switch staged {
        case .clean, .holdsTheHunk, .divergesFromTheWorktree, .addsLinesThatAreNotUTF8: ""
        case .holdsAnotherVersion: stagedStays + "\n\n"
        case .unreadable: stagedUnknown + "\n\n"
        }
    }
}

import Foundation

public enum ProjectInstructions {
    public enum Subject: String, Sendable, Hashable, CaseIterable {
        case merge
        case fixConflicts
    }

    public enum Extra: Sendable, Hashable {
        case nothing
        case file(String)
        case inline(String)
    }

    public static func projectPath(for subject: Subject) -> String {
        ".unifieddev/\(fileStem(for: subject))-instructions.md"
    }

    public static func scratchPath(for subject: Subject) -> String {
        "\(WorktreeScratch.generated)/\(fileStem(for: subject))-instructions.md"
    }

    public static func settingsKey(for subject: Subject) -> SettingsKey {
        switch subject {
        case .merge: .mergeInstructions
        case .fixConflicts: .conflictInstructions
        }
    }

    public static func stated(_ subject: Subject, in settings: RepoSettings) -> String? {
        switch subject {
        case .merge: settings.mergeInstructions
        case .fixConflicts: settings.conflictInstructions
        }
    }

    private static func fileStem(for subject: Subject) -> String {
        switch subject {
        case .merge: "merge"
        case .fixConflicts: "conflict"
        }
    }

    public static func resolve(
        _ subject: Subject, in worktree: String, stated: String?, authority: InstructionAuthority
    ) -> Extra {
        guard authority == .project else { return .nothing }
        return resolve(subject, in: worktree, stated: stated)
    }

    static func resolve(
        _ subject: Subject, in worktree: String, stated: String? = nil
    ) -> Extra {
        let project = projectPath(for: subject)
        if let text = readable(project, in: worktree), !text.isEmpty { return .file(project) }

        let typed = stated?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !typed.isEmpty else { return .nothing }
        guard let spilled = spill(typed, for: subject, in: worktree) else { return .inline(typed) }
        return .file(spilled)
    }

    public static func files(in worktree: String) -> [Subject: String] {
        var found: [Subject: String] = [:]
        for subject in Subject.allCases {
            let relative = projectPath(for: subject)
            guard let text = readable(relative, in: worktree), !text.isEmpty else { continue }
            found[subject] = relative
        }
        return found
    }

    private static func readable(_ relative: String, in worktree: String) -> String? {
        guard InstructionFile.isFile(relative, in: worktree) else { return nil }
        let full = (worktree as NSString).appendingPathComponent(relative)
        guard let text = try? String(contentsOfFile: full, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func spill(_ text: String, for subject: Subject, in worktree: String) -> String? {
        let relative = scratchPath(for: subject)
        WorktreeScratch.shield(WorktreeScratch.generated, in: worktree)
        let full = (worktree as NSString).appendingPathComponent(relative)
        guard (try? (text + "\n").write(toFile: full, atomically: true, encoding: .utf8)) != nil
        else { return nil }
        return InstructionFile.isFile(relative, in: worktree) ? relative : nil
    }

    public static func turn(
        _ rendered: String, for subject: Subject, adding extra: Extra, authority: InstructionAuthority,
        forge: ForgeKind = .gitHub
    ) -> String {
        var parts = [rendered.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let canonical = canonical(for: subject, authority: authority, forge: forge) { parts.append(canonical) }
        if let closing = sentence(for: subject, adding: extra) { parts.append(closing) }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    public static func canonical(
        for subject: Subject, authority: InstructionAuthority, forge: ForgeKind = .gitHub
    ) -> String? {
        guard subject == .merge else { return nil }
        if authority == .project { return MergeInstructions.canonical(for: forge) }
        return MergeInstructions.appOnly(for: forge)
    }

    public static func sentence(for subject: Subject, adding extra: Extra) -> String? {
        switch extra {
        case .nothing:
            return nil
        case .file(let path):
            return "\(preamble(for: subject)) Follow the instructions in "
                + "\(AttachmentDraft.token(for: path)) as well, and where they disagree with "
                + "anything above, they win."
        case .inline(let text):
            return "\(inlineLead(for: subject))\n\n\(text)"
        }
    }

    public static func inlineLead(for subject: Subject) -> String {
        "\(preamble(for: subject)) They could not be written to a file in this worktree, so they "
            + "are below. Where they disagree with anything above, they win."
    }

    private static func preamble(for subject: Subject) -> String {
        switch subject {
        case .merge: "This project has its own instructions for merging."
        case .fixConflicts: "This project has its own instructions for resolving merge conflicts."
        }
    }
}

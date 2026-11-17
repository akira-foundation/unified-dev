import Foundation

public enum CodeBlockCommand {
    static let runnableTags: Set<String> = ["sh", "shell", "bash", "zsh"]

    public static func runnable(code: String, info: String) -> String? {
        guard runnableTags.contains(Language.fenceTag(info)) else { return nil }
        let command = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    public static let outputLimit = 8 * 1_024 * 1_024

    public static func script(for command: String) -> String {
        "exec 2>&1\n" + command
    }
}

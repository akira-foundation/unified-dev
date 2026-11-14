import Foundation

public enum PreviewDataClaim {
    public static let recordName = "identity.env"

    public static func record(in root: String) -> String { root + "/" + recordName }

    public static func refusal(for identity: PreviewIdentity, recorded: String?, databaseExists: Bool) -> String? {
        guard databaseExists, let owner = appName(in: recorded), owner != identity.appName else { return nil }
        return "The preview data in \(identity.root) belongs to \(owner), built from another branch in this "
            + "worktree, so \(identity.appName) would open \(owner)'s projects. Run `make preview-clean`, "
            + "then build the preview again."
    }

    static func appName(in recorded: String?) -> String? {
        let lines = (recorded ?? "").split(whereSeparator: \.isNewline)
        let value = lines.first { $0.hasPrefix("app_name=") }?.dropFirst("app_name=".count)
        return value.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
    }
}

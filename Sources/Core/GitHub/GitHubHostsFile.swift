import Foundation

enum GitHubHostsFile {
    static let publicHost = "github.com"

    static func hostsHoldingTokens(in directory: URL) -> Set<String> {
        guard let contents = try? String(
            contentsOf: directory.appending(path: "hosts.yml"), encoding: .utf8
        ) else { return [] }
        var host: String?
        var holding: Set<String> = []
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard line.first?.isWhitespace == true else {
                host = trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : nil
                continue
            }
            guard let host, trimmed.hasPrefix("oauth_token:") else { continue }
            let value = trimmed.dropFirst("oauth_token:".count).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty, value != "\"\"", value != "''" { holding.insert(host) }
        }
        return holding
    }
}

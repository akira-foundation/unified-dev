import Foundation

extension Git {
    public static func remoteDefaultBranch(
        of directory: String, timeout: Duration = .seconds(5)
    ) async -> String? {
        guard let config = try? await repositoryConfiguration(in: directory) else { return nil }
        let current = (try? await currentBranch(of: directory)) ?? "HEAD"
        guard let remote = GitRepositoryContext.resolve(config: config, base: "main", branch: current).baseRemote,
              (try? validate(ref: remote, label: "remote")) != nil,
              let result = try? await runAgainstRemote(
                  ["ls-remote", "--symref", "--", remote, "HEAD"], in: directory, timeout: timeout
              ),
              result.ok,
              let branch = remoteHeadBranch(inListing: result.stdout)
        else { return nil }
        if await revision(of: "refs/remotes/\(remote)/\(branch)", in: directory) != nil { return branch }
        return await branchExists(branch, in: directory) ? branch : nil
    }

    static func remoteHeadBranch(inListing listing: String) -> String? {
        let prefix = "ref: refs/heads/"
        for line in listing.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, fields[1] == "HEAD", fields[0].hasPrefix(prefix) else { continue }
            let branch = String(fields[0].dropFirst(prefix.count))
            return isValidBranchName(branch) ? branch : nil
        }
        return nil
    }
}

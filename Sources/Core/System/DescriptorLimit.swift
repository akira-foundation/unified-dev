import Foundation
import os

public enum DescriptorLimit {
    public static let ceiling: rlim_t = 10240

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.akira.unifieddev",
        category: "descriptor-limit"
    )

    static func target(soft: rlim_t, hard: rlim_t) -> rlim_t? {
        let wanted = min(hard, ceiling)
        return wanted > soft ? wanted : nil
    }

    @discardableResult
    public static func raise() -> Bool {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            let code = errno
            log.error("could not read the descriptor limit: \(String(cString: strerror(code)), privacy: .public)")
            return false
        }
        guard let wanted = target(soft: limit.rlim_cur, hard: limit.rlim_max) else { return true }
        limit.rlim_cur = wanted
        guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            let code = errno
            log.error("could not raise the descriptor limit to \(wanted, privacy: .public): \(String(cString: strerror(code)), privacy: .public)")
            return false
        }
        return true
    }
}

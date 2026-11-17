import Foundation

public struct GitHubLoginRoutes: Sendable, Hashable {
    public struct Route: Sendable, Hashable {
        public let path: String
        public let profile: ProfileID

        public init(path: String, profile: ProfileID) {
            self.path = GitHubLoginRoutes.normalised(path)
            self.profile = profile
        }
    }

    public let routes: [Route]

    public init(routes: [Route]) {
        self.routes = routes.filter { !$0.path.isEmpty }.sorted {
            $0.path.count == $1.path.count ? $0.path < $1.path : $0.path.count > $1.path.count
        }
    }

    public func profile(forDirectory directory: String) -> ProfileID? {
        guard !directory.isEmpty else { return nil }
        let url = URL(filePath: directory)
        let ignoresCase = Self.volumeIgnoresCase(at: url)
        for wanted in [Self.normalised(directory), Self.normalised(url.resolvingSymlinksInPath().path)] {
            if let route = routes.first(where: { Self.holds($0.path, wanted, ignoringCase: ignoresCase) }) {
                return route.profile
            }
        }
        return nil
    }

    private static func volumeIgnoresCase(at url: URL) -> Bool {
        var probe = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" {
            probe = probe.deletingLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        return values?.volumeSupportsCaseSensitiveNames == false
    }

    private static func holds(_ route: String, _ wanted: String, ignoringCase: Bool) -> Bool {
        let route = ignoringCase ? route.lowercased() : route
        let wanted = ignoringCase ? wanted.lowercased() : wanted
        return wanted == route || wanted.hasPrefix(route == "/" ? "/" : route + "/")
    }

    static func normalised(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let standard = (path as NSString).standardizingPath
        return standard.count > 1 && standard.hasSuffix("/") ? String(standard.dropLast()) : standard
    }
}

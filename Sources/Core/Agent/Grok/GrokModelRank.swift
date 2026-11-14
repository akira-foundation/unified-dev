import Foundation

public enum GrokModelRank {
    public static func ordered(_ models: [ACPModel]) -> [ACPModel] {
        models.enumerated()
            .sorted { left, right in
                let a = key(left.element.id)
                let b = key(right.element.id)
                if a.version != b.version { return a.version.isAbove(b.version) }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    public static func recognises(_ raw: String) -> Bool {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return id == "grok" || id.hasPrefix("grok-") || id.hasPrefix("grok_")
    }

    private struct Key {
        var version: ModelVersion
    }

    private static func key(_ id: String) -> Key {
        Key(version: ModelVersion.parse(fromGrok: id))
    }
}

private struct ModelVersion: Comparable {
    var parts: [Int]

    static func parse(fromGrok id: String) -> ModelVersion {
        let lower = id.lowercased()
        let body = lower.hasPrefix("grok-") ? String(lower.dropFirst(5))
            : lower.hasPrefix("grok_") ? String(lower.dropFirst(5))
            : lower
        let numeric = body.split { !$0.isNumber && $0 != "." }
            .first
            .map(String.init) ?? ""
        let parts = numeric.split(separator: ".").compactMap { Int($0) }
        return ModelVersion(parts: parts)
    }

    func isAbove(_ other: ModelVersion) -> Bool {
        let count = max(parts.count, other.parts.count)
        for index in 0..<count {
            let a = index < parts.count ? parts[index] : 0
            let b = index < other.parts.count ? other.parts[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    static func < (lhs: ModelVersion, rhs: ModelVersion) -> Bool {
        rhs.isAbove(lhs)
    }
}

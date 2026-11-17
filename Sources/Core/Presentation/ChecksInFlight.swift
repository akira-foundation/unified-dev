import Foundation

public enum ChecksInFlight {
    public static let longestLine = 34

    public static func line(_ runs: [CheckRun]) -> String? {
        let running = names(of: runs, in: .running)
        let queued = names(of: runs, in: .queued)
        if !running.isEmpty {
            let trailer = queued.isEmpty ? "" : ", \(queued.count) queued"
            return "Running: " + listed(running, within: longestLine - "Running: ".count - trailer.count) + trailer
        }
        guard !queued.isEmpty else { return nil }
        return "Queued: " + listed(queued, within: longestLine - "Queued: ".count)
    }

    private static func names(of runs: [CheckRun], in state: CheckState) -> [String] {
        var seen = Set<String>()
        return runs
            .filter { CheckState($0) == state }
            .map(\.name)
            .filter { seen.insert($0).inserted }
    }

    private static func listed(_ names: [String], within room: Int) -> String {
        var shown = [names[0]]
        for name in names.dropFirst() {
            let left = names.count - shown.count - 1
            let candidate = (shown + [name]).joined(separator: ", ") + more(left)
            guard candidate.count <= room else { break }
            shown.append(name)
        }
        return shown.joined(separator: ", ") + more(names.count - shown.count)
    }

    private static func more(_ count: Int) -> String {
        count > 0 ? " and \(count) more" : ""
    }
}

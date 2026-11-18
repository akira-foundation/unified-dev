import Foundation

public extension SetupReport {
    var checkToOpen: SetupCheck? {
        guard verdict == .blocked, let first = blocking.first, let fix = first.fix, !fix.isInteractive
        else { return nil }
        return first
    }
}

public struct SetupDetailAutoOpen: Sendable, Hashable {
    public private(set) var hasNavigated = false

    public init() {}

    public mutating func readerNavigated() {
        hasNavigated = true
    }

    public mutating func check(toOpenIn report: SetupReport) -> SetupCheck? {
        guard !hasNavigated, let check = report.checkToOpen else { return nil }
        hasNavigated = true
        return check
    }
}

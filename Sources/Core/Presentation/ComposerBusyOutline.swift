import Foundation

public enum ComposerBusyOutline {
    public struct Stop: Equatable, Sendable {
        public let location: Double
        public let opacity: Double
    }

    public static let lap: TimeInterval = 3

    public static let width = 3.0

    public static let fade: TimeInterval = 0.25

    public static let faint = 0.08

    public static let stops = [
        Stop(location: 0, opacity: faint),
        Stop(location: 0.72, opacity: faint),
        Stop(location: 0.88, opacity: 1),
        Stop(location: 1, opacity: faint),
    ]

    public static func isSpinning(isBusy: Bool, reduceMotion: Bool) -> Bool {
        isBusy && !reduceMotion
    }

    public static func gradientSide(width: Double, height: Double) -> Double {
        guard width > 0, height > 0 else { return 0 }
        return hypot(width, height) + Self.width
    }
}

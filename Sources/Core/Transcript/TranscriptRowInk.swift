import Foundation

public enum TranscriptRowInk {
    public static let probeLength = 256

    private static let initMarker = Data("\"subtype\":\"init".utf8)
    private static let hookMarker = Data("\"hook_".utf8)

    public static func drawsNothing(kind: MessageKind, payload: Data) -> Bool {
        guard kind == .system else { return false }
        return payload.prefix(probeLength).range(of: initMarker) == nil
            && !BackgroundWake.isRow(kind: kind, payload: payload)
    }

    public static func namesHook(kind: MessageKind, payload: Data) -> Bool {
        kind == .system && payload.prefix(probeLength).range(of: hookMarker) != nil
    }
}

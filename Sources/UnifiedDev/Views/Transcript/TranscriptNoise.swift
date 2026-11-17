import Foundation
import Core

enum TranscriptNoise {
    static func isHidden(_ row: TranscriptRow) -> Bool {
        if row.kind == .notice || AppRequest.isHidden(kind: row.kind, payload: row.payload) { return true }
        return TranscriptRowInk.namesHook(kind: row.kind, payload: row.payload)
    }
}

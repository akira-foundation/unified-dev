import SwiftUI
import Core

enum MatchedRuns {
    static func text(_ string: String, highlights: [Int]) -> Text {
        var built = AttributedString()
        for run in MatchedRun.split(string, highlights: highlights) {
            var piece = AttributedString(run.text)
            if run.isHit { piece.inlinePresentationIntent = .stronglyEmphasized }
            built.append(piece)
        }
        return Text(built)
    }

    static func append(
        _ string: String,
        highlights: [Int],
        loud: Color,
        quiet: Color,
        to runs: inout LocalizedStringKey.StringInterpolation
    ) {
        for run in MatchedRun.split(string, highlights: highlights) {
            let piece = Text(run.text)
            let weighted = run.isHit ? piece.fontWeight(.bold) : piece
            runs.appendInterpolation(weighted.foregroundStyle(run.isLoud ? loud : quiet))
        }
    }
}

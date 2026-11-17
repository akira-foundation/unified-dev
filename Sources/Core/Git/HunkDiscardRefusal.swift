import Foundation

public enum HunkDiscardRefusal: Error, Sendable, Equatable {
    case notOffered
    case changed
    case indexDiffers
    case doesNotApply(String)
}

extension HunkDiscardRefusal: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notOffered:
            "A single hunk cannot be discarded from this diff."
        case .changed:
            "The file changed since this diff was drawn, so the hunk is not there any more. "
                + "Nothing was discarded."
        case .indexDiffers:
            "This file has staged changes that do not match the working file, so this hunk cannot "
                + "leave both of them in one step. Nothing was discarded. " + HunkDiscard.unstageFirst
        case let .doesNotApply(detail):
            "The hunk no longer applies cleanly, so nothing was discarded."
                + (detail.isEmpty ? "" : "\n\n" + detail)
        }
    }
}

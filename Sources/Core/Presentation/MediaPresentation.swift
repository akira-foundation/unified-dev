import Foundation
import UniformTypeIdentifiers

public enum MediaPresentation: Equatable, Sendable {
    case pages
    case still

    public static func of(path: String) -> MediaPresentation? {
        guard let type = UTType(filenameExtension: (path as NSString).pathExtension) else {
            return nil
        }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) { return nil }
        if type.conforms(to: .pdf) { return .pages }
        let stills: [UTType] = [.image, .audiovisualContent, .archive, .font]
        return stills.contains { type.conforms(to: $0) } ? .still : nil
    }
}

public enum MediaDisplay: Equatable, Sendable {
    case pages
    case counting
    case still

    public static func of(path: String, pageCount: Int?, hasCounted: Bool) -> MediaDisplay {
        guard MediaPresentation.of(path: path) == .pages else { return .still }
        guard hasCounted else { return .counting }
        return pageCount == nil ? .still : .pages
    }
}

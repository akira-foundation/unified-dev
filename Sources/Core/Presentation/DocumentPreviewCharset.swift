import Foundation

public enum DocumentPreviewCharset {
    static let prescanLength = 1_024

    private static let utf8Suffix = "; charset=utf-8"
    private static let labelCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789._:-")
    private static let utf16Labels: Set<String> = [
        "csunicode", "iso-10646-ucs-2", "ucs-2", "unicode", "unicodefeff", "unicodefffe",
    ]
    private static let stylesheet = try? NSRegularExpression(pattern: "^@charset \"([^\"]*)\";")

    public static func contentType(forFile path: String, body: Data) -> String {
        let type = DocumentPreview.contentType(forFile: path)
        guard type.hasSuffix(utf8Suffix), !type.hasPrefix("application/json") else { return type }
        let mime = String(type.dropLast(utf8Suffix.count))
        guard let label = label(for: body, path: path) else { return mime }
        return "\(mime); charset=\(label)"
    }

    public static func label(for body: Data, path: String) -> String? {
        if let marked = byteOrderMark(body) { return marked }
        if let declared = declared(in: body, path: path) { return declared }
        return String(data: body, encoding: .utf8) == nil ? nil : "utf-8"
    }

    private static func declared(in body: Data, path: String) -> String? {
        guard let prescan = String(data: body.prefix(prescanLength), encoding: .isoLatin1) else { return nil }
        if DocumentPreview.hasPreview(path: path) { return HTMLMetaCharset.declared(in: prescan, accepting: normalised) }
        guard (path as NSString).pathExtension.lowercased() == "css", let stylesheet,
              let match = stylesheet.firstMatch(in: prescan, range: NSRange(prescan.startIndex..., in: prescan)),
              let range = Range(match.range(at: 1), in: prescan) else { return nil }
        return normalised(String(prescan[range]))
    }

    private static func byteOrderMark(_ body: Data) -> String? {
        let head = Array(body.prefix(3))
        if head == [0xEF, 0xBB, 0xBF] { return "utf-8" }
        if head.starts(with: [0xFF, 0xFE]) { return "utf-16le" }
        if head.starts(with: [0xFE, 0xFF]) { return "utf-16be" }
        return nil
    }

    private static func normalised(_ label: String) -> String? {
        let lowered = label.lowercased()
        guard !lowered.isEmpty, lowered.count <= 40, lowered.allSatisfy(labelCharacters.contains) else { return nil }
        if lowered.hasPrefix("utf-16") || utf16Labels.contains(lowered) { return "utf-8" }
        if lowered == "x-user-defined" { return "windows-1252" }
        return lowered
    }
}

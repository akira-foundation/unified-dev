import CoreGraphics
import Foundation

public enum ReadablePDF {
    public struct Opened: Equatable, Sendable {
        public var pageCount: Int
        public var isLocked: Bool

        public init(pageCount: Int, isLocked: Bool) {
            self.pageCount = pageCount
            self.isLocked = isLocked
        }
    }

    public static func pageCount(atPath path: String) -> Int? {
        guard let document = CGPDFDocument(URL(filePath: path) as CFURL) else { return nil }
        if !document.isUnlocked, !document.unlockWithPassword("") { return nil }
        return document.numberOfPages > 0 ? document.numberOfPages : nil
    }

    public static func agreedPageCount(counted: Int?, opened: Opened?) -> Int? {
        guard counted != nil, let opened, !opened.isLocked, opened.pageCount > 0 else { return nil }
        return opened.pageCount
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import Core

@Suite("Readable PDF", .scratchDirectory)
struct ReadablePDFTests {
    private func pdf(pages: Int, password: String? = nil, owner: String? = nil) throws -> String {
        let path = TestScratch.unique("document") + ".pdf"
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        var info: [CFString: Any] = [:]
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password + " owner"
        }
        if let owner { info[kCGPDFContextOwnerPassword] = owner }
        let context = try #require(CGContext(URL(filePath: path) as CFURL, mediaBox: &box, info as CFDictionary))
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.fill(CGRect(x: 72, y: 72, width: 100, height: 100))
            context.endPDFPage()
        }
        context.closePDF()
        return path
    }

    private func file(_ contents: String) throws -> String {
        let path = TestScratch.unique("document") + ".pdf"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    @Test("Every page of a document is counted, not only the first")
    func countsEveryPage() throws {
        #expect(ReadablePDF.pageCount(atPath: try pdf(pages: 3)) == 3)
    }

    @Test("A document that asks for a password has no pages to show")
    func lockedHasNoPages() throws {
        let path = try pdf(pages: 2, password: "secret")
        #expect(CGPDFDocument(URL(filePath: path) as CFURL)?.isEncrypted == true)
        #expect(ReadablePDF.pageCount(atPath: path) == nil)
    }

    @Test("A document whose password is empty opens like any other")
    func emptyPasswordIsReadable() throws {
        let path = try pdf(pages: 2, password: "")
        #expect(CGPDFDocument(URL(filePath: path) as CFURL)?.isEncrypted == true)
        #expect(ReadablePDF.pageCount(atPath: path) == 2)
    }

    @Test("A document locked only against editing opens like any other")
    func ownerPasswordIsReadable() throws {
        let path = try pdf(pages: 4, password: "", owner: "editor")
        #expect(CGPDFDocument(URL(filePath: path) as CFURL)?.isEncrypted == true)
        #expect(ReadablePDF.pageCount(atPath: path) == 4)
    }

    @Test("A file that is not a PDF, or is empty, has no pages to show", arguments: ["not a pdf at all", ""])
    func unreadableHasNoPages(contents: String) throws {
        #expect(ReadablePDF.pageCount(atPath: try file(contents)) == nil)
    }

    @Test("A file that is gone has no pages to show")
    func missingHasNoPages() {
        #expect(ReadablePDF.pageCount(atPath: TestScratch.unique("gone") + ".pdf") == nil)
    }

    @Test("Pages are shown only when both readers open the document with pages", arguments: [
        (Int?.some(3), ReadablePDF.Opened?.some(.init(pageCount: 3, isLocked: false)), Int?.some(3)),
        (nil, .some(.init(pageCount: 3, isLocked: false)), nil),
        (3, nil, nil),
        (3, .some(.init(pageCount: 3, isLocked: true)), nil),
        (3, .some(.init(pageCount: 0, isLocked: false)), nil),
    ])
    func bothReadersAgree(counted: Int?, opened: ReadablePDF.Opened?, shown: Int?) {
        #expect(ReadablePDF.agreedPageCount(counted: counted, opened: opened) == shown)
    }
}

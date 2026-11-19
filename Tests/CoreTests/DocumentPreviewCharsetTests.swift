import Foundation
import Testing
@testable import Core

@Suite("Document preview charsets", .scratchDirectory)
struct DocumentPreviewCharsetTests {
    private func served(_ bytes: [UInt8], as name: String) throws -> DocumentPreviewAnswer {
        let path = TestScratch.unique("charset") + "-" + name
        try Data(bytes).write(to: URL(filePath: path))
        return DocumentPreviewAnswer.read(URL(filePath: path), draft: nil)
    }

    private func latin1(_ text: String) -> [UInt8] {
        Array(text.data(using: .isoLatin1) ?? Data())
    }

    @Test("a page that declares ISO-8859-1 in its meta is served as ISO-8859-1")
    func metaCharset() throws {
        let page = latin1("<html><head><meta charset=\"ISO-8859-1\"></head><body>caf\u{e9}</body></html>")
        let answer = try served(page, as: "report.html")
        #expect(answer.type == "text/html; charset=iso-8859-1")
        #expect(answer.body == Data(page))
    }

    @Test("the older http-equiv form of the declaration is honoured as well")
    func httpEquiv() throws {
        let page = latin1(
            "<meta http-equiv='Content-Type' content='text/html; charset=windows-1252'><p>na\u{ef}ve</p>"
        )
        #expect(try served(page, as: "old.htm").type == "text/html; charset=windows-1252")
    }

    @Test("a declaration inside a comment or past the first kilobyte is not read")
    func prescanOnly() throws {
        let commented = latin1("<!-- <meta charset=\"iso-8859-1\"> --><p>plain</p>")
        #expect(try served(commented, as: "commented.html").type == "text/html; charset=utf-8")
        let late = latin1(String(repeating: " ", count: 1_100) + "<meta charset=\"iso-8859-1\"><p>caf\u{e9}</p>")
        #expect(try served(late, as: "late.html").type == "text/html")
    }

    @Test("a byte order mark wins over the meta, as it does in a browser")
    func byteOrderMark() throws {
        let utf8 = [0xEF, 0xBB, 0xBF] + Array("<meta charset=\"iso-8859-1\">".utf8)
        #expect(try served(utf8, as: "bom.html").type == "text/html; charset=utf-8")
        let littleEndian: [UInt8] = [0xFF, 0xFE, 0x3C, 0x00]
        #expect(try served(littleEndian, as: "le.html").type == "text/html; charset=utf-16le")
        let bigEndian: [UInt8] = [0xFE, 0xFF, 0x00, 0x3C]
        #expect(try served(bigEndian, as: "be.html").type == "text/html; charset=utf-16be")
    }

    @Test("a meta naming UTF-16 without a byte order mark means UTF-8")
    func utf16LabelIsUTF8() throws {
        let page = Array("<meta charset=\"utf-16\"><p>x</p>".utf8)
        #expect(try served(page, as: "sixteen.html").type == "text/html; charset=utf-8")
    }

    @Test("a stylesheet that opens with @charset is served in that charset")
    func stylesheetCharset() throws {
        let sheet = latin1("@charset \"ISO-8859-1\";\nh1::after { content: \"\u{e9}\" }")
        #expect(try served(sheet, as: "style.css").type == "text/css; charset=iso-8859-1")
    }

    @Test("text that declares nothing and is not UTF-8 is served with no charset at all")
    func undeclaredLegacyText() throws {
        let script = latin1("document.title = \"caf\u{e9}\";")
        #expect(try served(script, as: "app.js").type == "text/javascript")
        let sheet = latin1("h1::after { content: \"\u{e9}\" }")
        #expect(try served(sheet, as: "plain.css").type == "text/css")
    }

    @Test("text that declares nothing and is UTF-8 is still declared UTF-8")
    func undeclaredUTF8() throws {
        let script = Array("document.title = \"caf\u{e9}\";".utf8)
        #expect(try served(script, as: "app.mjs").type == "text/javascript; charset=utf-8")
        let page = Array("<p>caf\u{e9}</p>".utf8)
        #expect(try served(page, as: "page.html").type == "text/html; charset=utf-8")
    }

    @Test("a label that is not a charset name is ignored rather than put in the header")
    func hostileLabel() throws {
        let page = Array("<meta charset=\"utf-8\r\nX-Evil: 1\"><p>x</p>".utf8)
        #expect(try served(page, as: "evil.html").type == "text/html; charset=utf-8")
        let long = Array("<meta charset=\"\(String(repeating: "a", count: 80))\">".utf8)
        #expect(try served(long, as: "long.html").type == "text/html; charset=utf-8")
    }

    @Test("JSON and binary types keep the type they had")
    func fixedTypes() throws {
        #expect(try served(latin1("{\"a\": \"\u{e9}\"}"), as: "data.json").type == "application/json; charset=utf-8")
        #expect(try served([0x89, 0x50, 0x4E, 0x47], as: "flow.png").type == "image/png")
    }

    @Test("an unsaved draft is sent as the UTF-8 it was encoded in, whatever its meta says")
    func draftStaysUTF8() throws {
        let path = TestScratch.unique("charset") + "-draft.html"
        try Data(latin1("<meta charset=\"iso-8859-1\">")).write(to: URL(filePath: path))
        let answer = DocumentPreviewAnswer.read(
            URL(filePath: path), draft: "<meta charset=\"iso-8859-1\"><p>caf\u{e9}</p>"
        )
        #expect(answer.type == "text/html; charset=utf-8")
        #expect(answer.body == Data("<meta charset=\"iso-8859-1\"><p>caf\u{e9}</p>".utf8))
    }
}

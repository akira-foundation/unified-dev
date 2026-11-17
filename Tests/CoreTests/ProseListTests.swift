import Foundation
import Testing
@testable import Core

@Suite("Words listed as a sentence would")
struct ProseListTests {
    @Test("none, one, two and three")
    func lists() {
        #expect(ProseList.joined([]) == "")
        #expect(ProseList.joined(["slipway"]) == "slipway")
        #expect(ProseList.joined(["slipway", "harbour"]) == "slipway and harbour")
        #expect(ProseList.joined(["a", "b", "c"]) == "a, b and c")
    }
}

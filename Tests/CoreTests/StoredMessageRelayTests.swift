import Foundation
import Testing
@testable import Core

@Suite("Rows a runner hands over with the event")
struct StoredMessageRelayTests {
    private static func stored(_ seq: Int, bytes: Int = 10) -> Message {
        Message(sessionID: SessionID("relay"), seq: seq, kind: .assistantText, payload: Data(repeating: 0x20, count: bytes))
    }

    @Test("every row up to the event's own is handed over in order")
    func handsOverAContiguousRun() {
        let relay = StoredMessageRelay()
        for seq in [7, 5, 6] { relay.deposit(Self.stored(seq)) }

        let taken = relay.take(after: 4, through: 7)

        #expect(taken?.map(\.seq) == [5, 6, 7])
        #expect(relay.heldCount == 0)
        #expect(relay.heldBytes == 0)
    }

    @Test("a row the runner never wrote means the store has to be read")
    func aGapIsNotAnswered() {
        let relay = StoredMessageRelay()
        for seq in [5, 7] { relay.deposit(Self.stored(seq)) }

        #expect(relay.take(after: 4, through: 7) == nil)
        #expect(relay.heldCount == 0)
    }

    @Test("an event the screen has already read past is not answered")
    func nothingNewIsNotAnswered() {
        let relay = StoredMessageRelay()
        relay.deposit(Self.stored(3))

        #expect(relay.take(after: 3, through: 3) == nil)
        #expect(relay.take(after: 5, through: 3) == nil)
        #expect(relay.heldCount == 0)
    }

    @Test("rows after the event stay for the next one")
    func laterRowsWait() {
        let relay = StoredMessageRelay()
        for seq in 1...4 { relay.deposit(Self.stored(seq)) }

        #expect(relay.take(after: 0, through: 2)?.map(\.seq) == [1, 2])
        #expect(relay.take(after: 2, through: 4)?.map(\.seq) == [3, 4])
    }

    @Test("rows the screen read from the store are dropped when it next asks")
    func staleRowsGo() {
        let relay = StoredMessageRelay()
        for seq in 1...4 { relay.deposit(Self.stored(seq)) }

        #expect(relay.take(after: 3, through: 4)?.map(\.seq) == [4])
        #expect(relay.heldCount == 0)
    }

    @Test("the oldest rows go first once the count is reached")
    func boundedByCount() {
        let relay = StoredMessageRelay(maxItems: 3)
        for seq in 1...5 { relay.deposit(Self.stored(seq)) }

        #expect(relay.heldCount == 3)
        #expect(relay.take(after: 0, through: 5) == nil)
    }

    @Test("the oldest rows go first once the bytes are reached")
    func boundedByBytes() {
        let relay = StoredMessageRelay(maxBytes: 250)
        for seq in 1...3 { relay.deposit(Self.stored(seq, bytes: 100)) }

        #expect(relay.heldCount == 2)
        #expect(relay.heldBytes == 200)
        #expect(relay.take(after: 1, through: 3)?.map(\.seq) == [2, 3])
    }

    @Test("a row written twice is held once and counted once")
    func aRewrittenRowReplaces() {
        let relay = StoredMessageRelay()
        relay.deposit(Self.stored(1, bytes: 100))
        relay.deposit(Self.stored(1, bytes: 40))

        #expect(relay.heldCount == 1)
        #expect(relay.heldBytes == 40)
    }

    @Test("a rewind forgets every row, so a reused seq is never answered with an old one")
    func clearingForgetsEverything() {
        let relay = StoredMessageRelay()
        for seq in 8...10 { relay.deposit(Self.stored(seq, bytes: 30)) }

        relay.clear()

        #expect(relay.heldCount == 0)
        #expect(relay.heldBytes == 0)
        #expect(relay.take(after: 7, through: 10) == nil)
    }
}

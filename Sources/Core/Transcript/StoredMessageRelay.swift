import Foundation
import Synchronization

public final class StoredMessageRelay: Sendable {
    private struct Held {
        var bySeq: [Int: Message] = [:]
        var bytes = 0

        mutating func remove(_ seq: Int) {
            guard let removed = bySeq.removeValue(forKey: seq) else { return }
            bytes -= removed.payload.count
        }
    }

    private let held = Mutex(Held())
    private let maxItems: Int
    private let maxBytes: Int

    public init(maxItems: Int = 128, maxBytes: Int = 16 * 1_024 * 1_024) {
        self.maxItems = max(1, maxItems)
        self.maxBytes = max(1, maxBytes)
    }

    public var heldCount: Int { held.withLock { $0.bySeq.count } }
    public var heldBytes: Int { held.withLock { $0.bytes } }

    public func deposit(_ message: Message) {
        held.withLock { value in
            value.remove(message.seq)
            value.bySeq[message.seq] = message
            value.bytes += message.payload.count
            while value.bySeq.count > maxItems || value.bytes > maxBytes, let oldest = value.bySeq.keys.min() {
                value.remove(oldest)
            }
        }
    }

    public func take(after seen: Int, through last: Int) -> [Message]? {
        held.withLock { value in
            defer {
                let settled = value.bySeq.keys.filter { $0 <= max(seen, last) }
                for seq in settled { value.remove(seq) }
            }
            guard last > seen else { return nil }
            let found = (seen + 1...last).compactMap { value.bySeq[$0] }
            return found.count == last - seen ? found : nil
        }
    }

    public func clear() {
        held.withLock { $0 = Held() }
    }
}

import Foundation
import Network
import Testing

final class LoopbackListener: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var seen = 0

    private init(_ listener: NWListener) {
        self.listener = listener
    }

    static func start(_ parameters: NWParameters) async throws -> LoopbackListener {
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let wrapper = LoopbackListener(try NWListener(using: parameters))
        wrapper.listener.newConnectionHandler = { [wrapper] connection in
            wrapper.lock.withLock { wrapper.seen += 1 }
            connection.cancel()
        }
        wrapper.listener.start(queue: .global())
        let deadline = ContinuousClock.now + .seconds(5)
        while wrapper.port == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(wrapper.port != 0, "the loopback listener never got a port")
        return wrapper
    }

    var port: UInt16 {
        listener.port?.rawValue ?? 0
    }

    var arrivals: Int {
        lock.withLock { seen }
    }

    func stop() {
        listener.cancel()
    }
}

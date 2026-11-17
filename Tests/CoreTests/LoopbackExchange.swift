import Foundation
import Synchronization

struct LoopbackExchange: Sendable {
    let connected: Bool
    let received: Int
    let failure: Int32

    var wasAnswered: Bool { received > 0 }
    var isStillWaiting: Bool { connected && received < 0 && (failure == EAGAIN || failure == EWOULDBLOCK) }
    var wasClosedUnanswered: Bool { failure == ECONNRESET || (connected && received == 0) }

    static func port(of url: String) -> UInt16? {
        guard let components = URLComponents(string: url), components.scheme == "http",
              components.host == "127.0.0.1", let port = components.port else { return nil }
        return UInt16(exactly: port)
    }

    static func sendAtOnce(_ request: String, to ports: [UInt16], waiting: Duration) async -> [LoopbackExchange?] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let answers = Mutex([LoopbackExchange?](repeating: nil, count: ports.count))
                DispatchQueue.concurrentPerform(iterations: ports.count) { index in
                    let answer = send(request, to: ports[index], waiting: waiting)
                    answers.withLock { $0[index] = answer }
                }
                continuation.resume(returning: answers.withLock { $0 })
            }
        }
    }

    static func send(_ request: String, to port: UInt16, waiting: Duration) -> LoopbackExchange? {
        let client = socket(AF_INET, SOCK_STREAM, 0)
        guard client >= 0 else { return nil }
        defer { close(client) }
        _ = fcntl(client, F_SETFD, FD_CLOEXEC)
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return LoopbackExchange(connected: false, received: -1, failure: errno) }
        _ = request.withCString { Darwin.send(client, $0, strlen($0), 0) }
        let microseconds = waiting.components.seconds * 1_000_000 + waiting.components.attoseconds / 1_000_000_000_000
        var wait = timeval(tv_sec: Int(microseconds / 1_000_000), tv_usec: Int32(microseconds % 1_000_000))
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        var buffer = [UInt8](repeating: 0, count: 64)
        var received = recv(client, &buffer, buffer.count, 0)
        while received < 0, errno == EINTR { received = recv(client, &buffer, buffer.count, 0) }
        return LoopbackExchange(connected: true, received: received, failure: received < 0 ? errno : 0)
    }
}

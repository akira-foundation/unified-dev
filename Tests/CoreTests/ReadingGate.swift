import Foundation

actor ReadingGate {
    private var isReached = false
    private var isOpen = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        isReached = true
        arrival?.resume()
        arrival = nil
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func reached() async {
        guard !isReached else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

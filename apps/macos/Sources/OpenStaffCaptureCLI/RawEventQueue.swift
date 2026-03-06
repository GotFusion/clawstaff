import Foundation

final class RawEventQueue {
    private var buffer: [RawEvent] = []
    private let lock = NSLock()

    @discardableResult
    func enqueue(_ event: RawEvent) -> Int {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(event)
        return buffer.count
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }

        return buffer.count
    }
}

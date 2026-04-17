import Foundation

/// Tiny ring-buffer log for in-app surfaces (the dashboard's live log pane, future
/// overlays, etc). Thread-safe because commands can emit from any queue (sensors use a
/// background queue for AX).
///
/// Design pattern: **Observer / PubSub** with polled read. The dashboard polls the most
/// recent entries on its refresh tick instead of pushing every log through a notification
/// — cheaper and avoids reentrancy risk during rendering.
final class EngineLog {
    struct Entry {
        enum Kind { case info, action, warn, error }
        let time: Date
        let kind: Kind
        let message: String
    }

    private let lock = NSLock()
    private var buffer: [Entry] = []
    /// How many entries to retain. Small — the UI only shows a handful anyway.
    private let capacity: Int = 120

    func info(_ msg: String)   { append(.info,   msg) }
    func action(_ msg: String) { append(.action, msg) }
    func warn(_ msg: String)   { append(.warn,   msg) }
    func error(_ msg: String)  { append(.error,  msg) }

    /// Read the most recent `n` entries, newest last. Returns a copy.
    func tail(_ n: Int) -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        if buffer.count <= n { return buffer }
        return Array(buffer.suffix(n))
    }

    private func append(_ kind: Entry.Kind, _ message: String) {
        let e = Entry(time: Date(), kind: kind, message: message)
        lock.lock()
        buffer.append(e)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        lock.unlock()
        // Mirror to Console so `swift run` output is still useful.
        NSLog("[colay] %@", message)
    }
}

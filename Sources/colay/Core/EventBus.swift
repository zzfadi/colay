import Foundation

/// Typed publish/subscribe bus. Decouples producers (sensors, input) from consumers
/// (behaviors, HUD, command handlers) and lets us throttle producers when nobody listens.
///
/// Design pattern: **Observer / Event Bus** with strongly-typed events. Every event type
/// conforms to `Event` (marker). Handlers are keyed by type and stored behind a token so
/// subscribers can deterministically unsubscribe.
///
/// Threading: all delivery happens on the main queue — we publish from the frame tick and
/// from main-thread AX callbacks. Sensors doing background work must hop back to main before
/// publishing. This keeps the render/behavior path lock-free.
protocol Event {}

final class EventBus {
    /// Opaque unsubscribe token.
    final class Token {
        fileprivate let key: ObjectIdentifier
        fileprivate let id: UUID
        fileprivate weak var bus: EventBus?
        fileprivate init(key: ObjectIdentifier, id: UUID, bus: EventBus) {
            self.key = key; self.id = id; self.bus = bus
        }
        deinit { bus?.unsubscribe(self) }
    }

    private struct Handler {
        let id: UUID
        let fn: (Any) -> Void
    }

    private var handlers: [ObjectIdentifier: [Handler]] = [:]
    private var subscriberCounts: [ObjectIdentifier: Int] = [:]

    /// Returns a Token — keep it alive for as long as you want to receive events.
    @discardableResult
    func subscribe<E: Event>(_ type: E.Type, _ handler: @escaping (E) -> Void) -> Token {
        dispatchPrecondition(condition: .onQueue(.main))
        let key = ObjectIdentifier(type)
        let id = UUID()
        let h = Handler(id: id) { any in
            if let e = any as? E { handler(e) }
        }
        handlers[key, default: []].append(h)
        subscriberCounts[key, default: 0] += 1
        return Token(key: key, id: id, bus: self)
    }

    func publish<E: Event>(_ event: E) {
        dispatchPrecondition(condition: .onQueue(.main))
        let key = ObjectIdentifier(E.self)
        guard let hs = handlers[key] else { return }
        for h in hs { h.fn(event) }
    }

    /// Number of live subscribers for a given event type. Sensors use this to decide
    /// whether to bother polling at all.
    func subscriberCount<E: Event>(_ type: E.Type) -> Int {
        let key = ObjectIdentifier(type)
        return subscriberCounts[key] ?? 0
    }

    fileprivate func unsubscribe(_ token: Token) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard var list = handlers[token.key] else { return }
        list.removeAll { $0.id == token.id }
        handlers[token.key] = list.isEmpty ? nil : list
        subscriberCounts[token.key, default: 0] -= 1
        if subscriberCounts[token.key] ?? 0 <= 0 {
            subscriberCounts.removeValue(forKey: token.key)
        }
    }
}

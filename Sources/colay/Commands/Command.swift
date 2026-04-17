import Foundation

/// A **Command** is one atomic, programmable unit of work — the public surface area of
/// colay. Every script action, every menu item, and every future AI tool call resolves to
/// a Command.
///
/// Design pattern: **Command + Prototype**. Each Command is a self-contained object with
/// a lifecycle (`start` → `update` until `isFinished` → optional cleanup in `cancel`).
/// New commands are created by their type's `factory` from a typed `Params` struct, which
/// doubles as the JSON schema for the AI-tool bridge.
///
/// Contract:
/// - `start` is called once, on the main thread. It may complete synchronously by setting
///   `finish()`.
/// - `update(dt:)` is called every frame on the main thread until `isFinished` is true.
/// - `cancel` is called if the scheduler interrupts the command (e.g. script reloaded).
protocol Command: AnyObject {
    var id: UUID { get }
    var isFinished: Bool { get }
    func start(services: Services)
    func update(dt: TimeInterval, services: Services)
    /// Called when the scheduler cancels this command before it finishes naturally.
    /// Implementations should clean up resources but MUST NOT call `finish()`.
    func cancel(services: Services)
}

/// Convenience base class that satisfies the protocol with sane defaults.
class BaseCommand: Command {
    let id: UUID = UUID()
    private(set) var isFinished: Bool = false
    func start(services: Services) {}
    func update(dt: TimeInterval, services: Services) {}
    func cancel(services: Services) { isFinished = true }
    func finish() { isFinished = true }
}

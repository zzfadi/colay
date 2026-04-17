import Foundation

/// Executes commands over time. Two queues:
///   - `sequence`: one-at-a-time, FIFO. This is what a script becomes.
///   - `background`: commands running concurrently alongside the sequence (e.g. a
///     highlight fade while the next move happens).
///
/// Design pattern: **Scheduler / Coroutine runner**. Commands cooperatively yield by
/// setting `isFinished`. This keeps the concurrency model trivial — no locks, no async
/// reentrancy — and is easy to pause, cancel, and time-scale through the Clock.
final class CommandScheduler {
    private(set) var sequence: [Command] = []
    private var current: Command?
    private var background: [Command] = []

    private(set) var isPaused: Bool = false

    /// Whole-program metadata captured once at load so `loop` can replay it cheaply.
    private var program: [(String, CommandParams)] = []
    private var loopProgram: Bool = false

    /// Load a fresh program, cancelling anything in flight.
    func load(program: [(String, CommandParams)], loop: Bool, registry: CommandRegistry,
              services: Services) {
        cancelAll(services: services)
        self.program = program
        self.loopProgram = loop
        self.sequence = program.compactMap { registry.make(type: $0.0, params: $0.1) }
    }

    func enqueue(_ c: Command) { sequence.append(c) }
    func runInBackground(_ c: Command, services: Services) {
        c.start(services: services)
        if !c.isFinished { background.append(c) }
    }

    func cancelAll(services: Services) {
        current?.cancel(services: services); current = nil
        for c in sequence { c.cancel(services: services) }
        sequence.removeAll()
        for c in background { c.cancel(services: services) }
        background.removeAll()
    }

    func setPaused(_ p: Bool) { isPaused = p }

    func tick(dt: TimeInterval, services: Services) {
        guard !isPaused else { return }

        // Sequence: run head until it finishes, then advance. At most one command started
        // per tick — keeps behavior deterministic and avoids burning CPU.
        if current == nil {
            if sequence.isEmpty, loopProgram, !program.isEmpty {
                sequence = program.compactMap {
                    services.registry.make(type: $0.0, params: $0.1)
                }
            }
            if !sequence.isEmpty {
                current = sequence.removeFirst()
                current?.start(services: services)
            }
        }
        if let c = current {
            c.update(dt: dt, services: services)
            if c.isFinished { current = nil }
        }

        // Background: prune finished, tick the rest.
        background.removeAll { c in
            c.update(dt: dt, services: services)
            return c.isFinished
        }
    }
}

import Foundation

/// Central catalog of every command the engine can execute. This is the **single seam**
/// that a future AI tool-calling layer will bind to: one registry, one dispatch path,
/// schemas exposed for introspection.
///
/// Design pattern: **Registry + Factory**. Each command type registers a builder keyed by
/// its type name. The Scheduler / ScriptLoader / (future) tool-call bridge all dispatch
/// through `make(type:params:)`.
final class CommandRegistry {
    typealias Factory = (CommandParams) -> Command?

    private struct Entry {
        let schema: CommandSchema
        let factory: Factory
    }

    private var entries: [String: Entry] = [:]

    /// Register a command type. Calling twice for the same type replaces the previous
    /// entry (useful for hot-reload during development).
    func register(_ schema: CommandSchema, factory: @escaping Factory) {
        entries[schema.type] = Entry(schema: schema, factory: factory)
    }

    func make(type: String, params: CommandParams) -> Command? {
        guard let e = entries[type] else {
            NSLog("[colay] Unknown command type: \(type)")
            return nil
        }
        // Expose `self` to composites (parallel/sequence) so their factories can recurse
        // into the registry without needing it passed in explicitly. Set on main thread
        // only, restored after the factory returns.
        let prev = CommandRegistry.current
        CommandRegistry.current = self
        defer { CommandRegistry.current = prev }
        return e.factory(params)
    }

    /// Current registry in scope of a `make` call. Only valid on the main thread.
    static var current: CommandRegistry?

    var schemas: [CommandSchema] {
        entries.values.map { $0.schema }.sorted { $0.type < $1.type }
    }

    /// Dump the registry as JSON-Schema-ish manifest for external consumers (e.g. to feed
    /// an AI tool-caller). Not used at runtime yet, but the shape is stable.
    func manifest() -> [[String: Any]] {
        schemas.map { s in
            [
                "type": s.type,
                "summary": s.summary,
                "parameters": s.params.map { p in
                    [
                        "name": p.name,
                        "type": p.type,
                        "required": p.required,
                        "description": p.description
                    ] as [String: Any]
                }
            ]
        }
    }
}

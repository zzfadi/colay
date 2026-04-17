import CoreGraphics
import Foundation

/// Continuous AI-ish behaviors attached to a node. Unlike one-shot Commands, behaviors are
/// **steady-state**: they produce a steering force every frame until removed or replaced.
///
/// Design pattern: **Strategy + Composite (behavior stack with weighted blending)**. The
/// BehaviorComponent holds a prioritized list of behaviors; each frame they all contribute,
/// weighted, and the resulting force is handed to the PhysicsComponent. This is the exact
/// technique used in game AI (boids, NPC locomotion) and is what gives the character a
/// sense of "life" without hard-coding any animations.
final class BehaviorComponent: Component {
    struct Slot {
        let id: UUID
        var behavior: Behavior
        var weight: CGFloat
        var name: String
    }

    private(set) var slots: [Slot] = []

    @discardableResult
    func add(_ behavior: Behavior, weight: CGFloat = 1.0, name: String = "") -> UUID {
        let id = UUID()
        slots.append(Slot(id: id, behavior: behavior, weight: weight, name: name))
        return id
    }

    func remove(id: UUID) {
        slots.removeAll { $0.id == id }
    }

    func remove(named name: String) {
        slots.removeAll { $0.name == name }
    }

    func clear() { slots.removeAll() }

    /// Clear only behaviors that are NOT in `preserveOnPrimarySwap`. Used by `stop` mode
    /// to park the avatar without shredding the ambient bumpers.
    func clearTransient() {
        slots.removeAll { !preserveOnPrimarySwap.contains($0.name) }
    }

    /// Names of "ambient" behaviors that are part of the simulation chassis (e.g. the
    /// screen bumper) and should survive `setPrimary` swaps. Without this, swapping the
    /// primary mode would also delete the bumper and the character would drift off
    /// screen.
    var preserveOnPrimarySwap: Set<String> = ["stayOnScreen"]

    /// Replace the primary behavior(s) with a new one, preserving any ambient slots in
    /// `preserveOnPrimarySwap`. Used by mode commands ("idle", "follow cursor", ...).
    func setPrimary(_ behavior: Behavior, name: String) {
        slots.removeAll { !preserveOnPrimarySwap.contains($0.name) }
        add(behavior, weight: 1.0, name: name)
    }

    func has(named name: String) -> Bool {
        slots.contains { $0.name == name }
    }
}

/// A unit of continuous movement logic. Receives the node's current state and returns a
/// desired force contribution for this frame.
protocol Behavior: AnyObject {
    func update(ctx: BehaviorContext) -> CGPoint
}

/// Everything a behavior needs to decide. Kept as a struct so behaviors can't mutate the
/// world directly — they only return forces. This keeps the system predictable and
/// debuggable.
struct BehaviorContext {
    let node: Node
    let transform: TransformComponent
    let physics: PhysicsComponent
    let dt: TimeInterval
    let time: TimeInterval
    let services: Services
}

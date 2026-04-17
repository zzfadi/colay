import CoreGraphics
import Foundation

/// Point-mass physics: force → acceleration → velocity → position.
///
/// Design pattern: **data component, integrated by a system**. The PhysicsSystem walks nodes
/// with this component and applies symplectic Euler each frame. Behaviors *don't* write
/// position directly — they accumulate a `steering` force, which is the composable
/// primitive that makes "feels natural" possible (Reynolds 1999).
final class PhysicsComponent: Component {
    /// Current velocity in points/sec.
    var velocity: CGPoint = .zero
    /// Accumulated force to apply this frame. Zeroed by the system after integration.
    var steering: CGPoint = .zero
    /// Upper bound on speed; prevents the character from rocketing off when multiple
    /// behaviors stack up.
    var maxSpeed: CGFloat = 900
    /// Upper bound on |steering| each frame. "How snappy" — smaller = lazier.
    var maxForce: CGFloat = 2400
    /// Multiplier per-second drag. 0.92 means 8%/s lost to friction.
    var damping: CGFloat = 2.5
    /// If > 0, velocity is zeroed when magnitude falls below this. Prevents jitter at rest.
    var restThreshold: CGFloat = 0.5

    /// Mass for force = mass * accel. Keep at 1 unless a behavior specifically needs it.
    var mass: CGFloat = 1

    /// Helper for behaviors: add a force contribution (will be truncated by `maxForce`).
    func applyForce(_ f: CGPoint) { steering += f }
}

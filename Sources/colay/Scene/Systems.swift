import CoreGraphics
import Foundation

/// Walks the scene, asks each BehaviorComponent for its weighted sum of forces, and pushes
/// the result into the node's PhysicsComponent as `steering`. The actual motion happens in
/// PhysicsSystem next.
final class BehaviorSystem {
    func update(root: Node, dt: TimeInterval, time: TimeInterval, services: Services) {
        visit(root, dt: dt, time: time, services: services)
    }

    private func visit(_ node: Node, dt: TimeInterval, time: TimeInterval, services: Services) {
        if let bc = node.component(BehaviorComponent.self),
           bc.enabled,
           let phys = node.component(PhysicsComponent.self),
           phys.enabled {
            var total = CGPoint.zero
            let ctx = BehaviorContext(
                node: node, transform: node.transform, physics: phys,
                dt: dt, time: time, services: services
            )
            for slot in bc.slots {
                let f = slot.behavior.update(ctx: ctx)
                total += f * slot.weight
            }
            phys.applyForce(total)
        }
        for c in node.children { visit(c, dt: dt, time: time, services: services) }
    }
}

/// Symplectic Euler integration: velocity += accel*dt; position += velocity*dt.
/// Applies per-second damping so motion decays smoothly without tuning per-frame constants.
final class PhysicsSystem {
    func update(root: Node, dt: TimeInterval) {
        guard dt > 0 else { return }
        visit(root, dt: dt)
    }

    private func visit(_ node: Node, dt: TimeInterval) {
        if let phys = node.component(PhysicsComponent.self),
           phys.enabled {
            // Clamp accumulated steering to maxForce (Reynolds).
            let force = phys.steering.truncated(max: phys.maxForce)
            let accel = force / max(phys.mass, 0.0001)
            var v = phys.velocity + accel * CGFloat(dt)

            // Per-second exponential damping.
            let decay = CGFloat(exp(-Double(phys.damping) * dt))
            v = v * decay

            // Cap speed.
            v = v.truncated(max: phys.maxSpeed)

            // Rest snap to kill infinitesimal jitter.
            if v.length < phys.restThreshold { v = .zero }

            phys.velocity = v
            node.transform.position += v * CGFloat(dt)
            phys.steering = .zero // consumed this frame
        }
        for c in node.children { visit(c, dt: dt) }
    }
}

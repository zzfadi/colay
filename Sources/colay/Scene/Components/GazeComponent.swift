import CoreGraphics
import Foundation
import AppKit

/// Where the character's eyes should look. First-class scene concern — *not* something
/// commands should poke into the drawable directly.
///
/// Design pattern: **Component** (data) + **System** (per-frame computation). The
/// component stores a declarative intent ("look at the cursor", "look ahead along my
/// velocity", "look at this point"). A `GazeSystem` walks the tree each frame and turns
/// that intent into a concrete look vector that the drawable consumes.
///
/// Commands and behaviors that want the character to glance somewhere push an **override**
/// onto the stack; when they end they pop it, and the base target takes over again. This
/// way the eyes are never stuck "pointing at the last command's target" after the command
/// finished.
enum GazeTarget {
    /// No driver — eyes relax to straight ahead (slightly up).
    case idle
    /// Track the system cursor.
    case cursor
    /// Track a fixed point in overlay-local coords.
    case point(CGPoint)
    /// Look in the direction the body is moving (anticipatory glance).
    case velocity
}

final class GazeComponent: Component {
    /// Base target — what the eyes do when nobody's overriding. Defaults to cursor so the
    /// character always feels aware of the user.
    var base: GazeTarget = .cursor

    /// Short-lived overrides pushed by commands / behaviors. Highest index wins. Each
    /// override carries an id so its owner can remove it when it finishes.
    private(set) var overrides: [(id: UUID, target: GazeTarget)] = []

    /// How quickly the current look vector catches up with the desired one (per-second
    /// exponential). Higher = snappier. This is what gives the saccade + smooth-pursuit
    /// feel instead of teleporting pupils.
    var smoothing: CGFloat = 14

    /// The resolved local-space look vector for this frame. Written by `GazeSystem`, read
    /// by the drawable.
    private(set) var look: CGPoint = CGPoint(x: 0, y: 40)

    @discardableResult
    func pushOverride(_ target: GazeTarget) -> UUID {
        let id = UUID()
        overrides.append((id, target))
        return id
    }

    func removeOverride(id: UUID) {
        overrides.removeAll { $0.id == id }
    }

    /// Current effective target (top of stack, or base).
    var effective: GazeTarget { overrides.last?.target ?? base }

    /// Called by GazeSystem.
    func setLook(_ p: CGPoint) { look = p }
}

/// Turns `GazeComponent.effective` into a concrete per-frame look vector.
final class GazeSystem {
    func update(root: Node, dt: TimeInterval, services: Services) {
        visit(root, dt: dt, services: services)
    }

    private func visit(_ node: Node, dt: TimeInterval, services: Services) {
        if let gaze = node.component(GazeComponent.self), gaze.enabled {
            let desired = resolve(target: gaze.effective, node: node, services: services)
            // Exponential smoothing toward desired.
            let alpha = CGFloat(1 - exp(-Double(gaze.smoothing) * dt))
            let next = CGPoint(
                x: gaze.look.x + (desired.x - gaze.look.x) * alpha,
                y: gaze.look.y + (desired.y - gaze.look.y) * alpha
            )
            gaze.setLook(next)

            // Push the resolved look vector into any CharacterDrawable on this node. The
            // drawable is a pure consumer — it never decides where to look itself.
            if let rc = node.component(RenderComponent.self),
               let character = rc.drawable as? CharacterDrawable {
                character.lookTarget = next
            }
        }
        for c in node.children { visit(c, dt: dt, services: services) }
    }

    private func resolve(target: GazeTarget, node: Node, services: Services) -> CGPoint {
        switch target {
        case .idle:
            return CGPoint(x: 0, y: 40)
        case .cursor:
            let m = NSEvent.mouseLocation
            let f = services.overlay.frame
            let local = CGPoint(x: m.x - f.origin.x, y: m.y - f.origin.y)
            return local - node.transform.position
        case .point(let p):
            return p - node.transform.position
        case .velocity:
            if let phys = node.component(PhysicsComponent.self) {
                let v = phys.velocity
                if v.length < 5 { return CGPoint(x: 0, y: 40) }
                // Project ~80pt ahead so the drawable sees a meaningful vector.
                return v.normalized() * 80
            }
            return CGPoint(x: 0, y: 40)
        }
    }
}

import CoreGraphics
import Foundation

// MARK: - Steering primitives (Reynolds)
//
// These are the atoms of motion. They never read state outside of BehaviorContext and
// return a force, nothing else. Compose them by adding multiple slots to a
// BehaviorComponent with different weights.

/// Steer toward a static point at full speed. Force = desired - velocity.
final class SeekBehavior: Behavior {
    var target: CGPoint
    init(target: CGPoint) { self.target = target }
    func update(ctx: BehaviorContext) -> CGPoint {
        let desired = (target - ctx.transform.position).normalized() * ctx.physics.maxSpeed
        return desired - ctx.physics.velocity
    }
}

/// Steer toward a point but slow down within a radius. The natural "park smoothly"
/// behavior — used for moveTo commands and for settling next to the cursor without the
/// character overshooting.
final class ArriveBehavior: Behavior {
    var target: CGPoint
    var slowingRadius: CGFloat
    init(target: CGPoint, slowingRadius: CGFloat = 180) {
        self.target = target; self.slowingRadius = max(slowingRadius, 1)
    }
    func update(ctx: BehaviorContext) -> CGPoint {
        let offset = target - ctx.transform.position
        let dist = offset.length
        if dist < 0.5 { return ctx.physics.velocity * -1 } // brake
        let speed = dist < slowingRadius
            ? ctx.physics.maxSpeed * (dist / slowingRadius)
            : ctx.physics.maxSpeed
        let desired = offset.normalized() * speed
        return desired - ctx.physics.velocity
    }
}

/// Cursor companion. Unlike "stuck to the cursor", this orbits nearby with:
///   1. Arrive toward cursor + an angular offset so it doesn't sit ON the cursor
///   2. A small dead-zone so tiny mouse jitters don't cause visible motion
///   3. Wander noise blended in so it feels alive when the cursor is still
///
/// The offset orbits slowly so over time the character appears on different sides.
final class FollowCursorBehavior: Behavior {
    /// How far from the cursor to try to sit, in points.
    var orbitRadius: CGFloat = 110
    /// How fast the offset angle rotates (radians/sec). Small = character drifts around you slowly.
    var orbitSpeed: Double = 0.45
    /// Radius inside which the character considers itself "close enough" and just idles.
    var deadZone: CGFloat = 8
    /// Arrive slowing radius.
    var slowingRadius: CGFloat = 140

    private let wander = WanderBehavior(strength: 0.25)
    private let mouse: () -> CGPoint

    init(mouseProvider: @escaping () -> CGPoint) {
        self.mouse = mouseProvider
    }

    func update(ctx: BehaviorContext) -> CGPoint {
        let m = mouse()
        let angle = ctx.time * orbitSpeed
        let offset = CGPoint(x: cos(angle), y: sin(angle)) * orbitRadius
        let target = m + offset

        let d = (target - ctx.transform.position).length
        if d < deadZone {
            return wander.update(ctx: ctx) * 0.5 - ctx.physics.velocity * 0.3
        }

        let dist = (target - ctx.transform.position).length
        let speed = dist < slowingRadius
            ? ctx.physics.maxSpeed * (dist / slowingRadius)
            : ctx.physics.maxSpeed
        let desired = (target - ctx.transform.position).normalized() * speed
        let arrive = desired - ctx.physics.velocity
        return arrive + wander.update(ctx: ctx) * 0.3
    }
}

/// Classic Reynolds wander. Instead of returning a fuzzy direction vector (which gets
/// eaten by damping and looks like a stall), we project a **wander circle** ahead of the
/// character and seek a point on that circle that jitters each frame. The result is a
/// full-strength seek force toward a slowly-drifting target — visibly lively, never
/// stalling.
///
/// Pattern:  target = position + velocity.normalized() * lookAhead
///                  + (cos(θ), sin(θ)) * circleRadius
///           θ += random jitter each frame
final class WanderBehavior: Behavior {
    /// How far in front of the character the wander circle floats. Bigger = smoother,
    /// more lazy motion.
    var lookAhead: CGFloat = 90
    /// Radius of the jitter circle. Bigger = sharper turns.
    var circleRadius: CGFloat = 60
    /// Max radians per second the wander angle can change.
    var angularSpeed: Double = 3.0
    /// Force multiplier. 1 = full steering force.
    var strength: CGFloat

    private var angle: CGFloat

    init(strength: CGFloat = 1.0) {
        self.strength = strength
        self.angle = CGFloat.random(in: 0..<(2 * .pi))
    }

    func update(ctx: BehaviorContext) -> CGPoint {
        // Jitter the angle. Random in ±angularSpeed * dt.
        angle += CGFloat.random(in: -CGFloat(angularSpeed)...CGFloat(angularSpeed)) * CGFloat(ctx.dt)

        // Forward axis — if we're basically stationary, pick a direction from the current angle.
        let v = ctx.physics.velocity
        let forward: CGPoint = v.length > 5 ? v.normalized()
                                            : CGPoint(x: cos(angle), y: sin(angle))
        let circleCenter = ctx.transform.position + forward * lookAhead
        let offset = CGPoint(x: cos(angle), y: sin(angle)) * circleRadius
        let target = circleCenter + offset

        let desired = (target - ctx.transform.position).normalized() * ctx.physics.maxSpeed
        let steer = desired - v
        return steer * strength
    }
}

/// Gentle idle bob: vertical breathing when the character is at rest. Does nothing when
/// the character is actively moving (length of velocity above threshold). Stacks cleanly
/// with others.
final class IdleBobBehavior: Behavior {
    var amplitude: CGFloat = 12   // points
    var frequency: Double = 1.1   // Hz
    var activeThreshold: CGFloat = 40 // if speed above, contribute nothing

    func update(ctx: BehaviorContext) -> CGPoint {
        if ctx.physics.velocity.length > activeThreshold { return .zero }
        let w = 2 * .pi * frequency
        // Desired vertical velocity = derivative of amplitude*sin(wt) = amplitude*w*cos(wt)
        let vy = amplitude * CGFloat(w) * CGFloat(cos(w * ctx.time))
        let desired = CGPoint(x: 0, y: vy)
        return desired - ctx.physics.velocity * CGFloat(0.3)
    }
}

/// Keep the character within the screen bounds with a soft bumper (exponential spring
/// force that gets stronger near the edge). Prevents it from wandering off-screen.
final class StayOnScreenBehavior: Behavior {
    var bounds: () -> CGRect
    var margin: CGFloat = 60
    var stiffness: CGFloat = 8.0

    init(boundsProvider: @escaping () -> CGRect) { self.bounds = boundsProvider }

    func update(ctx: BehaviorContext) -> CGPoint {
        let r = bounds().insetBy(dx: margin, dy: margin)
        let p = ctx.transform.position
        var f = CGPoint.zero
        if p.x < r.minX { f.x += (r.minX - p.x) * stiffness }
        if p.x > r.maxX { f.x -= (p.x - r.maxX) * stiffness }
        if p.y < r.minY { f.y += (r.minY - p.y) * stiffness }
        if p.y > r.maxY { f.y -= (p.y - r.maxY) * stiffness }
        return f
    }
}

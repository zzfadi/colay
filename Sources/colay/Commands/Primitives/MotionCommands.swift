import CoreGraphics
import Foundation
import AppKit

// Each primitive is tiny and does ONE thing. They never reach for globals; everything
// comes in through `services`. This is the surface a future AI tool-caller will bind to —
// new tools come from composing these, not from adding inheritance.

// MARK: - Motion

/// Fly to a point by installing a transient ArriveBehavior on the avatar and waiting
/// until it gets close. NOT a position snap — the physics system carries it there, which
/// is why movement looks natural.
final class FlyToCommand: BaseCommand {
    let target: CGPoint
    let arriveRadius: CGFloat
    let maxDuration: TimeInterval
    private var elapsed: TimeInterval = 0
    private var behaviorID: UUID?
    private var gazeID: UUID?

    init(target: CGPoint, arriveRadius: CGFloat = 6, maxDuration: TimeInterval = 6) {
        self.target = target
        self.arriveRadius = arriveRadius
        self.maxDuration = maxDuration
    }

    override func start(services: Services) {
        let b = ArriveBehavior(target: target, slowingRadius: 220)
        behaviorID = services.avatar.behaviors.add(b, weight: 1.0, name: "flyTo")
        // Look where we're going for the duration of the flight.
        gazeID = services.avatar.gaze.pushOverride(.point(target))
        services.log.action(String(format: "flyTo (%.0f, %.0f)", target.x, target.y))
    }

    override func update(dt: TimeInterval, services: Services) {
        elapsed += dt
        let pos = services.avatar.node.transform.position
        if pos.distance(to: target) < arriveRadius || elapsed >= maxDuration {
            finishAndCleanup(services: services)
        }
    }

    override func cancel(services: Services) {
        finishAndCleanup(services: services)
    }

    private func finishAndCleanup(services: Services) {
        if let id = behaviorID { services.avatar.behaviors.remove(id: id) }
        if let id = gazeID { services.avatar.gaze.removeOverride(id: id) }
        behaviorID = nil
        gazeID = nil
        finish()
    }
}

/// Installs FollowCursorBehavior as the primary for `duration` seconds.
final class FollowCursorCommand: BaseCommand {
    let duration: TimeInterval
    let orbitRadius: CGFloat
    private var elapsed: TimeInterval = 0
    private var behaviorID: UUID?

    init(duration: TimeInterval, orbitRadius: CGFloat = 110) {
        self.duration = duration
        self.orbitRadius = orbitRadius
    }

    override func start(services: Services) {
        let overlay = services.overlay
        let b = FollowCursorBehavior(mouseProvider: {
            // Convert global mouse → overlay-local coords.
            let mouse = NSEvent.mouseLocation
            let f = overlay.frame
            return CGPoint(x: mouse.x - f.origin.x, y: mouse.y - f.origin.y)
        })
        b.orbitRadius = orbitRadius
        behaviorID = services.avatar.behaviors.add(b, weight: 1.0, name: "followCursor")
        // Default gaze is already .cursor so no override needed.
    }

    override func update(dt: TimeInterval, services: Services) {
        elapsed += dt
        if elapsed >= duration { finishAndCleanup(services: services) }
    }

    override func cancel(services: Services) { finishAndCleanup(services: services) }

    private func finishAndCleanup(services: Services) {
        if let id = behaviorID { services.avatar.behaviors.remove(id: id) }
        finish()
    }
}

/// Just waits. Still participates in the Clock so it pauses cleanly.
final class WaitCommand: BaseCommand {
    let duration: TimeInterval
    private var elapsed: TimeInterval = 0
    init(duration: TimeInterval) { self.duration = duration }
    override func update(dt: TimeInterval, services: Services) {
        elapsed += dt
        if elapsed >= duration { finish() }
    }
}

// MARK: - Visual

final class ScaleToCommand: BaseCommand {
    let target: CGFloat; let duration: TimeInterval; let easing: Easing
    private var tween: Tween?
    init(target: CGFloat, duration: TimeInterval, easing: Easing) {
        self.target = target; self.duration = duration; self.easing = easing
    }
    override func start(services: Services) {
        let tr = services.avatar.node.transform
        let start = tr.scale; let end = target
        tween = Tween(duration: duration, easing: easing,
                      tick: { t in tr.scale = lerp(start, end, t) },
                      onComplete: { [weak self] in self?.finish() })
    }
    override func update(dt: TimeInterval, services: Services) { tween?.update(dt: dt) }
}

final class FadeToCommand: BaseCommand {
    let target: CGFloat; let duration: TimeInterval; let easing: Easing
    private var tween: Tween?
    init(target: CGFloat, duration: TimeInterval, easing: Easing) {
        self.target = target; self.duration = duration; self.easing = easing
    }
    override func start(services: Services) {
        let tr = services.avatar.node.transform
        let start = tr.alpha; let end = target
        tween = Tween(duration: duration, easing: easing,
                      tick: { t in tr.alpha = lerp(start, end, t) },
                      onComplete: { [weak self] in self?.finish() })
    }
    override func update(dt: TimeInterval, services: Services) { tween?.update(dt: dt) }
}

/// Little up-and-down hop (drives CharacterDrawable.hopPhase) — good "excited" beat.
final class HopCommand: BaseCommand {
    private var t: Double = 0
    let duration: TimeInterval
    init(duration: TimeInterval = 0.5) { self.duration = duration }
    override func start(services: Services) {
        services.log.action("hop")
    }
    override func update(dt: TimeInterval, services: Services) {
        t += dt / duration
        if t >= 1 {
            services.avatar.character.hopPhase = 0
            finish()
        } else {
            services.avatar.character.hopPhase = t
        }
    }
}

// MARK: - Diagnostics

final class LogCommand: BaseCommand {
    let message: String
    init(message: String) { self.message = message }
    override func start(services: Services) {
        services.log.info(message)
        finish()
    }
}

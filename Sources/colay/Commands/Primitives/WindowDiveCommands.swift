import AppKit
import CoreGraphics
import Foundation

// MARK: - Visual effect primitives
//
// Dive and emerge are exact mirrors of each other: the same motion, stretch, and scale
// curves played forward vs. reversed. That symmetry is what makes them read as a single
// "in / out" gesture rather than two unrelated animations.
//
// The "genie-into-bottle" read comes from combining three synchronized things:
//   1. a *direct* line toward the target (no swirl / no spin — those distract)
//   2. a vertical stretch (warpPhase) that funnels the body as if pulled through an
//      opening, handled inside CharacterDrawable so the eyes/sensors stretch with it
//   3. uniform scale collapsing toward the target point
// The quartic easing (p⁴) does all the "pulled by gravity / suction" acceleration work.

/// Dive: swoops from `from` into `to` while stretching and shrinking into the window.
/// Caller must call `start()` with the avatar already at `from`, or pass a matching
/// `from` — we set it explicitly so the effect is self-contained.
final class PlayDiveEffectCommand: BaseCommand {
    let from: CGPoint
    let to: CGPoint
    let duration: TimeInterval

    private var elapsed: TimeInterval = 0

    init(from: CGPoint, to: CGPoint, duration: TimeInterval = 0.55) {
        self.from = from
        self.to = to
        self.duration = duration
    }

    override func start(services: Services) {
        let n = services.avatar.node
        n.transform.position = from
        n.transform.rotation = 0
        n.transform.scale = 1
        n.transform.alpha = 1
        services.avatar.character.warpPhase = 0
    }

    override func update(dt: TimeInterval, services: Services) {
        elapsed += dt
        let p = CGFloat(min(1.0, elapsed / duration))

        // Quartic ease-in for position + scale: slow lean-in, then a hard pull at the
        // end — the defining shape of a "being sucked in" motion.
        let e = p * p * p * p

        let n = services.avatar.node
        n.transform.position = CGPoint(
            x: from.x + (to.x - from.x) * e,
            y: from.y + (to.y - from.y) * e
        )
        n.transform.scale = 1 - e
        // warpPhase ramps linearly so the stretch is visible through the whole motion,
        // not just at the end (where scale has already shrunk it to nothing).
        services.avatar.character.warpPhase = Double(p)
        // Tail-end alpha fade so the final frames disappear cleanly at the impact point.
        n.transform.alpha = p < 0.85 ? 1 : Double(1 - (p - 0.85) / 0.15)

        if p >= 1.0 {
            n.transform.scale = 0
            n.transform.alpha = 0
            services.avatar.character.warpPhase = 0
            finish()
        }
    }

    override func cancel(services: Services) {
        services.avatar.character.warpPhase = 0
        super.cancel(services: services)
    }
}

/// Emerge: the exact reverse — materializes at `from` (inside the window) and rises to
/// `to` (above the window) while un-stretching and scaling back to 1. Curves are mirror
/// images of dive's so the two animations compose into one continuous gesture.
final class PlayEmergeEffectCommand: BaseCommand {
    let from: CGPoint
    let to: CGPoint
    let duration: TimeInterval

    private var elapsed: TimeInterval = 0

    init(from: CGPoint, to: CGPoint, duration: TimeInterval = 0.55) {
        self.from = from
        self.to = to
        self.duration = duration
    }

    override func start(services: Services) {
        let n = services.avatar.node
        n.transform.position = from
        n.transform.rotation = 0
        n.transform.scale = 0
        n.transform.alpha = 0
        services.avatar.character.warpPhase = 1.0
    }

    override func update(dt: TimeInterval, services: Services) {
        elapsed += dt
        let p = CGFloat(min(1.0, elapsed / duration))

        // Quartic ease-out: explodes out fast, settles gently — mirror of the dive's
        // ease-in so the curves line up back-to-back.
        let e = 1 - pow(1 - p, 4)

        let n = services.avatar.node
        n.transform.position = CGPoint(
            x: from.x + (to.x - from.x) * e,
            y: from.y + (to.y - from.y) * e
        )
        n.transform.scale = e
        services.avatar.character.warpPhase = Double(1 - p)
        // Fast fade-in mirroring the dive's fade-out at the tail.
        n.transform.alpha = p < 0.15 ? Double(p / 0.15) : 1

        if p >= 1.0 {
            n.transform.scale = 1
            n.transform.alpha = 1
            services.avatar.character.warpPhase = 0
            finish()
        }
    }

    override func cancel(services: Services) {
        let n = services.avatar.node
        n.transform.scale = 1
        n.transform.alpha = 1
        services.avatar.character.warpPhase = 0
        super.cancel(services: services)
    }
}

// MARK: - Composites
//
// End-user commands. These orchestrate snapshot → effect → attachment state so the
// pure visual primitives above don't need to know anything about windows or sensors.

/// "Dive into the currently focused window": snapshot AX, play the dive from wherever
/// the avatar happens to be, then mark the avatar as attached to that window. The
/// attachment component is the state-bearing handle; future commands like click/type/
/// readText will target `services.avatar.attachment.target`.
final class DiveIntoFocusedWindowCommand: BaseCommand {
    private var child: Command?
    private var pendingAttachment: WindowTarget?

    override func start(services: Services) {
        services.log.action("dive: capturing focused window…")
        services.sensors.requestFocusedWindowSnapshot { [weak self] info in
            guard let self = self else { return }
            guard let bounds = info.bounds else {
                services.log.warn("dive: no window bounds, aborting")
                self.finish()
                return
            }
            let local = services.overlay.screenRectToLocal(bounds)
            let impact = CGPoint(x: local.midX, y: local.midY)
            let start = services.avatar.node.transform.position

            self.pendingAttachment = WindowTarget(
                pid: info.pid,
                appName: info.appName,
                title: info.windowTitle,
                bounds: bounds,
                axWindow: nil,
                attachedAt: services.clock.time
            )
            services.log.action("dive: entering \(info.appName ?? "window")")

            let effect = PlayDiveEffectCommand(from: start, to: impact)
            effect.start(services: services)
            self.child = effect
        }
    }

    override func update(dt: TimeInterval, services: Services) {
        guard let c = child else { return }
        c.update(dt: dt, services: services)
        if c.isFinished {
            if let t = pendingAttachment {
                services.avatar.attachment.attach(t)
                services.log.action("dive: attached to \(t.appName ?? "window")")
            }
            finish()
        }
    }

    override func cancel(services: Services) {
        child?.cancel(services: services)
        super.cancel(services: services)
    }
}

/// "Emerge from the currently attached window": bursts back out to a point just above
/// the window's top edge, then clears the attachment. No-op (with a warn log) if the
/// avatar isn't attached — the UI already disables this button in that state, but we
/// defend against script-triggered calls too.
final class EmergeFromWindowCommand: BaseCommand {
    private var child: Command?

    override func start(services: Services) {
        guard let t = services.avatar.attachment.target else {
            services.log.warn("emerge: not attached")
            finish()
            return
        }
        let local = services.overlay.screenRectToLocal(t.bounds)
        let impact = CGPoint(x: local.midX, y: local.midY)
        // Exit above the window — symmetrical with where a "dive from above" would enter.
        // Distance is shorter than dive travel so it reads as a pop-out rather than a flight.
        let exit = CGPoint(x: local.midX, y: local.maxY + 80)

        services.log.action("emerge: leaving \(t.appName ?? "window")")
        let effect = PlayEmergeEffectCommand(from: impact, to: exit)
        effect.start(services: services)
        child = effect
    }

    override func update(dt: TimeInterval, services: Services) {
        guard let c = child else { return }
        c.update(dt: dt, services: services)
        if c.isFinished {
            services.avatar.attachment.detach()
            services.log.action("emerge: detached")
            finish()
        }
    }

    override func cancel(services: Services) {
        child?.cancel(services: services)
        let n = services.avatar.node
        n.transform.scale = 1
        n.transform.alpha = 1
        n.transform.rotation = 0
        services.avatar.character.warpPhase = 0
        services.avatar.attachment.detach()
        super.cancel(services: services)
    }
}

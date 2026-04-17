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
/// Staged so the body visibly *travels* before collapsing, rather than vanishing at
/// the target:
///   • 0 – 65 %  — move toward the window with a gentle ease-in; body stays full size
///                 but the vertical stretch (warpPhase) is already ramping up
///   • 65 – 100 % — final suck-in at the window; scale and alpha collapse here
final class PlayDiveEffectCommand: BaseCommand {
    let from: CGPoint
    let to: CGPoint
    let duration: TimeInterval

    /// Fraction of the duration spent in the travel stage. The remainder is the collapse.
    private let travelFrac: CGFloat = 0.65

    private var elapsed: TimeInterval = 0

    init(from: CGPoint, to: CGPoint, duration: TimeInterval = 0.75) {
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

        let n = services.avatar.node

        // Position — ease-in-cubic over the whole duration. Cubic (p³) is softer than
        // quartic at the tail, which reads as "pulled" rather than "snapped" in.
        let moveE = p * p * p
        n.transform.position = CGPoint(
            x: from.x + (to.x - from.x) * moveE,
            y: from.y + (to.y - from.y) * moveE
        )

        // Stretch builds smoothly over the full motion (smoothstep) so the body is
        // already funneling before the final collapse — that's what sells the genie read.
        services.avatar.character.warpPhase = Double(smoothstep(p))

        if p < travelFrac {
            // Travel stage: stay at full size; only warp is changing.
            n.transform.scale = 1
            n.transform.alpha = 1
        } else {
            // Collapse stage: shrink + fade the last 35% over a cubic ease-in so the
            // disappearance itself has a "pulled through the hole" acceleration.
            let k = (p - travelFrac) / (1 - travelFrac)   // 0 → 1
            let ke = k * k * k
            n.transform.scale = 1 - ke
            // Alpha fades only in the very last sliver so the collapse is visible.
            n.transform.alpha = k < 0.75 ? 1 : Double(1 - (k - 0.75) / 0.25)
        }

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

/// Emerge: the mirror of dive, also staged. The avatar first **bulges out of the
/// window** (un-stretching, scaling up, fading in) without travelling, then **rises**
/// smoothly to the exit point. Without staging the cubic ease-out covered ~60 % of the
/// distance in the first 25 % of time — the body appeared to teleport up and then
/// snap back when behaviors took over.
///   • 0 – 35 %  — bulge out at `from`: scale 0→1, warpPhase 1→0, alpha 0→1
///   • 35 – 100 % — rise to `to` with a soft ease-out so it arrives, not crashes
final class PlayEmergeEffectCommand: BaseCommand {
    let from: CGPoint
    let to: CGPoint
    let duration: TimeInterval

    /// Fraction of the duration spent bulging in place before any travel begins.
    private let bulgeFrac: CGFloat = 0.35

    private var elapsed: TimeInterval = 0

    init(from: CGPoint, to: CGPoint, duration: TimeInterval = 0.85) {
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

        let n = services.avatar.node

        if p < bulgeFrac {
            // Bulge stage: hold position, push the body out of the opening.
            let k = p / bulgeFrac                       // 0 → 1
            let ke = 1 - pow(1 - k, 3)                  // ease-out-cubic
            n.transform.position = from
            n.transform.scale = ke
            n.transform.alpha = Double(min(1, k * 1.4)) // fade in slightly faster than scale
            services.avatar.character.warpPhase = Double(1 - ke)
        } else {
            // Rise stage: smooth ease-out from `from` to `to`. Quadratic feels gentler
            // than cubic for a "settling" motion — no perceived overshoot.
            let k = (p - bulgeFrac) / (1 - bulgeFrac)   // 0 → 1
            let ke = 1 - (1 - k) * (1 - k)              // ease-out-quad
            n.transform.position = CGPoint(
                x: from.x + (to.x - from.x) * ke,
                y: from.y + (to.y - from.y) * ke
            )
            n.transform.scale = 1
            n.transform.alpha = 1
            services.avatar.character.warpPhase = 0
        }

        if p >= 1.0 {
            n.transform.position = to
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

// MARK: - Easing helpers

/// Smoothstep on [0, 1]. Zero slope at both ends, monotonic, cheap.
@inline(__always)
private func smoothstep(_ x: CGFloat) -> CGFloat {
    let t = max(0, min(1, x))
    return t * t * (3 - 2 * t)
}

// MARK: - Composites
//
// End-user commands. These orchestrate snapshot → effect → attachment state so the
// pure visual primitives above don't need to know anything about windows or sensors.

/// Well-known scene node name for the "avatar is attached here" marker. We use a
/// name-based lookup so the emerge command can find and remove it without any shared
/// state between the two commands.
private let attachmentMarkerNodeName = "attachmentMarker"

/// Spawn (or replace) the attachment marker node at the given overlay-local rect.
/// Centralized so dive and emerge agree on geometry.
private func spawnAttachmentMarker(for localRect: CGRect, services: Services) {
    // If one is already present (e.g. quick re-dive without emerge), replace it.
    services.scene.root.find(name: attachmentMarkerNodeName)?.removeFromParent()

    let n = Node(name: attachmentMarkerNodeName)
    n.transform.position = localRect.origin
    n.transform.size = localRect.size
    n.transform.alpha = 1
    // Render behind the avatar (layer 10) but in front of anything else.
    n.addComponent(RenderComponent(AttachmentMarkerDrawable(), layer: 5))
    services.scene.root.addChild(n)
}

/// Remove the attachment marker if present. Safe to call unconditionally.
private func removeAttachmentMarker(services: Services) {
    services.scene.root.find(name: attachmentMarkerNodeName)?.removeFromParent()
}

/// "Dive into the currently focused window": snapshot AX, play the dive from wherever
/// the avatar happens to be, then mark the avatar as attached to that window. The
/// attachment component is the state-bearing handle; future commands like click/type/
/// readText will target `services.avatar.attachment.target`.
final class DiveIntoFocusedWindowCommand: BaseCommand {
    private var child: Command?
    private var pendingAttachment: WindowTarget?
    private var pendingLocalRect: CGRect?

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
                axWindow: info.axWindow,
                attachedAt: services.clock.time
            )
            self.pendingLocalRect = local
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
                if let rect = pendingLocalRect {
                    spawnAttachmentMarker(for: rect, services: services)
                }
                services.log.action("dive: attached to \(t.appName ?? "window")")
            }
            finish()
        }
    }

    override func cancel(services: Services) {
        child?.cancel(services: services)
        removeAttachmentMarker(services: services)
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
        // Exit just above the window's top edge — close enough that the avatar lands
        // visibly *next to* the window it came out of, far enough to read as "out".
        // Clamp into the overlay so it can't fly off-screen on windows near the top.
        let overlay = services.overlay.frame
        let margin: CGFloat = 40
        let rawExitY = local.maxY + 24
        let exitY = max(margin, min(overlay.height - margin, rawExitY))
        let exitX = max(margin, min(overlay.width - margin, local.midX))
        let exit = CGPoint(x: exitX, y: exitY)

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
            removeAttachmentMarker(services: services)
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
        removeAttachmentMarker(services: services)
        super.cancel(services: services)
    }
}

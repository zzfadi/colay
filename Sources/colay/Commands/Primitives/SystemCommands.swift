import AppKit
import CoreGraphics
import Foundation

// MARK: - Composites

/// Runs children concurrently, finishes when all do. Composition primitive.
final class ParallelCommand: BaseCommand {
    let children: [Command]
    init(_ children: [Command]) { self.children = children }
    override func start(services: Services) {
        for c in children { c.start(services: services) }
        if children.allSatisfy({ $0.isFinished }) { finish() }
    }
    override func update(dt: TimeInterval, services: Services) {
        for c in children where !c.isFinished { c.update(dt: dt, services: services) }
        if children.allSatisfy({ $0.isFinished }) { finish() }
    }
    override func cancel(services: Services) {
        for c in children where !c.isFinished { c.cancel(services: services) }
        super.cancel(services: services)
    }
}

/// Runs children in order. One seq = one mini-program; lets you nest inside a parallel.
final class SequenceCommand: BaseCommand {
    let children: [Command]
    private var idx: Int = 0
    private var started: Bool = false
    init(_ children: [Command]) { self.children = children }

    override func start(services: Services) {
        if children.isEmpty { finish(); return }
        children[0].start(services: services)
        started = true
    }

    override func update(dt: TimeInterval, services: Services) {
        guard started, idx < children.count else { finish(); return }
        let c = children[idx]
        c.update(dt: dt, services: services)
        if c.isFinished {
            idx += 1
            if idx < children.count {
                children[idx].start(services: services)
            } else {
                finish()
            }
        }
    }

    override func cancel(services: Services) {
        if idx < children.count { children[idx].cancel(services: services) }
        super.cancel(services: services)
    }
}

// MARK: - Sensors (on-demand)

/// Fetches the focused window's info once and publishes it on the EventBus. No polling.
/// This is how the script asks "tell me what's on top right now" without setting up a
/// continuous subscription.
final class CaptureFocusedWindowCommand: BaseCommand {
    override func start(services: Services) {
        services.log.info("snapshot: requesting focused window…")
        services.sensors.requestFocusedWindowSnapshot { info in
            let app = info.appName ?? "?"
            let title = info.windowTitle ?? "(untitled)"
            if let b = info.bounds {
                services.log.action(String(
                    format: "snapshot: %@ — %@ @ %.0f,%.0f %.0f×%.0f",
                    app, title, b.minX, b.minY, b.width, b.height
                ))
            } else {
                services.log.warn("snapshot: \(app) — \(title) (no bounds)")
            }
            services.bus.publish(info)
        }
        finish()
    }
}

/// Draws an animated highlight box around the focused window and fades out over
/// `duration`. The command itself stays alive while the highlight is visible (wrap in
/// `parallel` if you want the character to move during the highlight).
final class HighlightFocusedWindowCommand: BaseCommand {
    let duration: TimeInterval
    private var elapsed: TimeInterval = 0
    private weak var node: Node?

    init(duration: TimeInterval = 1.2) { self.duration = duration }

    override func start(services: Services) {
        services.sensors.requestFocusedWindowSnapshot { [weak self] info in
            guard let self = self, let rect = info.bounds else { self?.finish(); return }
            let localRect = services.overlay.screenRectToLocal(rect)
            let n = Node(name: "highlight")
            n.transform.position = localRect.origin
            n.transform.size = localRect.size
            n.addComponent(RenderComponent(HighlightRectDrawable(), layer: -1))
            services.scene.root.addChild(n)
            self.node = n
        }
    }

    override func update(dt: TimeInterval, services: Services) {
        elapsed += dt
        if let n = node {
            let p = min(elapsed / duration, 1.0)
            n.transform.alpha = CGFloat(1.0 - p)
        }
        if elapsed >= duration {
            node?.removeFromParent()
            finish()
        }
    }

    override func cancel(services: Services) {
        node?.removeFromParent()
        super.cancel(services: services)
    }
}

// MARK: - Input

/// Click at the avatar's current position (or an explicit `at`) via CGEvent. This is a
/// primitive — chain it with FlyTo to "fly somewhere and click".
final class ClickCommand: BaseCommand {
    let at: CGPoint?
    let button: String
    init(at: CGPoint?, button: String = "left") { self.at = at; self.button = button }
    override func start(services: Services) {
        let screen: CGPoint
        if let a = at {
            screen = services.overlay.localToScreen(a)
        } else {
            screen = services.overlay.localToScreen(services.avatar.node.transform.position)
        }
        services.input.click(at: screen, button: button)
        finish()
    }
}

/// Emit a Unicode string through the keyboard at `cps` characters per second.
final class TypeCommand: BaseCommand {
    let text: String; let cps: Double
    private var idx: String.Index!
    private var acc: Double = 0
    init(text: String, cps: Double) { self.text = text; self.cps = max(1, cps) }
    override func start(services: Services) {
        idx = text.startIndex
        if idx == text.endIndex { finish() }
    }
    override func update(dt: TimeInterval, services: Services) {
        acc += dt
        let interval = 1.0 / cps
        while acc >= interval, idx < text.endIndex {
            services.input.typeCharacter(text[idx])
            idx = text.index(after: idx)
            acc -= interval
        }
        if idx >= text.endIndex { finish() }
    }
}

// MARK: - Behavior controls

/// Replaces the avatar's primary behavior. Used by menu items ("stay idle", "follow me")
/// and by scripts. Instant — terminates immediately.
final class SetBehaviorCommand: BaseCommand {
    enum Mode: String { case idle, followCursor, wander, stop }
    let mode: Mode
    init(mode: Mode) { self.mode = mode }
    override func start(services: Services) {
        let b = services.avatar.behaviors
        switch mode {
        case .idle:
            b.setPrimary(IdleBobBehavior(), name: "idle")
            services.avatar.gaze.base = .cursor
        case .followCursor:
            let overlay = services.overlay
            let follow = FollowCursorBehavior(mouseProvider: {
                let m = NSEvent.mouseLocation
                let f = overlay.frame
                return CGPoint(x: m.x - f.origin.x, y: m.y - f.origin.y)
            })
            b.setPrimary(follow, name: "followCursor")
            services.avatar.gaze.base = .cursor
        case .wander:
            // Actual physical wander (Reynolds). The bumper stays (see
            // preserveOnPrimarySwap) so the character doesn't leave the screen.
            // Gaze follows velocity so the eyes look where we're drifting.
            b.setPrimary(WanderBehavior(strength: 1.0), name: "wander")
            services.avatar.gaze.base = .velocity
        case .stop:
            // Drop the primary (keep ambient bumpers) and park velocity.
            b.clearTransient()
            services.avatar.physics.velocity = .zero
            services.avatar.gaze.base = .idle
        }
        services.log.action("mode → \(mode.rawValue)")
        finish()
    }
}

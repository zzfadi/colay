import AppKit
import CoreGraphics
import Foundation

/// "Wander" mode, redesigned: instead of physically drifting around the screen, the
/// character stays in place (idle bob) and its **gaze** wanders across visible on-screen
/// windows. Picks a new window every couple of seconds, biased toward windows that are
/// actually inside the overlay (i.e. the user can see the character looking at them).
///
/// Lifetime: runs in the scheduler's background queue. Self-finishes the moment the
/// avatar's primary behavior is no longer named "lookAround" — this is how a mode swap
/// (Idle / Follow / Stop) cleans us up without needing explicit cancellation wiring.
final class LookAroundWindowsCommand: BaseCommand {

    /// How often to pick a new target, in seconds. Long enough to feel deliberate
    /// (saccade + dwell), short enough to feel curious.
    var dwell: TimeInterval = 2.2

    /// Skip windows smaller than this (px) — menu bar items, tiny utility palettes.
    var minWindowSide: CGFloat = 80

    private var elapsed: TimeInterval = 0
    private var pickIn: TimeInterval = 0
    private var ownPID: pid_t = getpid()
    private var lastTarget: CGPoint?

    override func start(services: Services) {
        // Pick immediately so the eyes don't sit on the cursor for a moment first.
        pickAndAim(services: services)
    }

    override func update(dt: TimeInterval, services: Services) {
        // Self-cleanup on mode change.
        if !services.avatar.behaviors.has(named: "lookAround") {
            services.avatar.gaze.base = .cursor
            finish()
            return
        }

        elapsed += dt
        pickIn -= dt
        if pickIn <= 0 {
            pickAndAim(services: services)
        }
    }

    override func cancel(services: Services) {
        services.avatar.gaze.base = .cursor
        finish()
    }

    // MARK: - Picking

    private func pickAndAim(services: Services) {
        pickIn = dwell
        let candidates = collectVisibleWindowCenters(services: services)
        guard !candidates.isEmpty else {
            // Nothing to look at — glance to a random spot inside the overlay.
            let f = services.overlay.frame
            let pad: CGFloat = 80
            let local = CGPoint(
                x: CGFloat.random(in: pad...(f.width - pad)),
                y: CGFloat.random(in: pad...(f.height - pad))
            )
            services.avatar.gaze.base = .point(local)
            lastTarget = local
            return
        }
        // Avoid picking the same window twice in a row.
        var pool = candidates
        if let prev = lastTarget, pool.count > 1 {
            pool.removeAll { hypot($0.x - prev.x, $0.y - prev.y) < 4 }
        }
        let pick = pool.randomElement() ?? candidates[0]
        services.avatar.gaze.base = .point(pick)
        lastTarget = pick
    }

    /// Returns centers (in overlay-local coords) of on-screen windows that intersect the
    /// overlay frame and are owned by other apps. The overlay itself is excluded.
    private func collectVisibleWindowCenters(services: Services) -> [CGPoint] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let overlayFrame = services.overlay.frame
        var out: [CGPoint] = []
        for info in raw {
            // Skip our own windows (the overlay + status bar).
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == ownPID { continue }
            // Skip Dock/menu/system layers — those have layer != 0.
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }
            // Bounds (top-left origin, screen coords).
            guard let bDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: bDict as CFDictionary) else {
                continue
            }
            if rect.width < minWindowSide || rect.height < minWindowSide { continue }
            // Convert to overlay-local (bottom-left). screenRectToLocal handles flip.
            let local = services.overlay.screenRectToLocal(rect)
            // Only keep windows visible inside the overlay viewport.
            let viewport = CGRect(origin: .zero, size: overlayFrame.size)
            let clipped = local.intersection(viewport)
            if clipped.isNull || clipped.width < 40 || clipped.height < 40 { continue }
            out.append(CGPoint(x: clipped.midX, y: clipped.midY))
        }
        return out
    }
}

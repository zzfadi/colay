import Foundation

/// Central time authority for the engine. Provides delta time, pause, and time-scaling.
///
/// Design pattern: **Singleton-per-engine service** (injected, not global). The Clock is the
/// only thing that advances game time. Physics, behaviors, tweens, and commands all read
/// `dt` from here — never from wall-clock directly. This makes pause/slow-mo trivial and
/// testing deterministic (inject a mock clock).
final class Clock {
    /// Seconds elapsed in the last tick, already scaled by `timeScale` and zeroed when paused.
    private(set) var dt: TimeInterval = 0

    /// Cumulative scaled time since start. Use for animations, not for timestamps.
    private(set) var time: TimeInterval = 0

    /// Unscaled raw wall time since start (advances even when paused). Use for UI blinking.
    private(set) var wallTime: TimeInterval = 0

    /// Global time multiplier. 1 = real-time, 0.5 = slow-mo, 2 = fast.
    var timeScale: Double = 1.0

    /// When paused, `dt` is 0 but `wallTime` still advances.
    var isPaused: Bool = false

    private var lastWall: CFTimeInterval = 0

    /// Advance the clock. Called once per frame by the Engine.
    func advance(now: CFTimeInterval) {
        if lastWall == 0 {
            lastWall = now
            dt = 0
            return
        }
        let raw = max(0, min(0.1, now - lastWall)) // clamp to avoid huge dt after stalls
        lastWall = now
        wallTime += raw
        if isPaused {
            dt = 0
        } else {
            dt = raw * timeScale
            time += dt
        }
    }
}

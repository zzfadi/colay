import Foundation

/// Small easing lib — used by Tweens and value commands (fade/scale) that don't need
/// the physics path. Behaviors prefer `smooth(dt, tau:)` over easings because they're
/// continuous and need to be frame-rate independent regardless of duration.
enum Easing: String, Codable {
    case linear, easeIn, easeOut, easeInOut, easeOutBack

    func apply(_ t: Double) -> Double {
        let t = clamp(t, 0, 1)
        switch self {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return 1 - (1 - t) * (1 - t)
        case .easeInOut: return t < 0.5 ? 2*t*t : 1 - pow(-2*t + 2, 2)/2
        case .easeOutBack:
            let c1 = 1.70158; let c3 = c1 + 1
            let p = t - 1
            return 1 + c3 * p * p * p + c1 * p * p
        }
    }
}

/// Tween: advance 0..1 progress by `dt`, call `tick(eased)` each frame, `onComplete` once.
final class Tween {
    let duration: TimeInterval
    let easing: Easing
    private let tick: (Double) -> Void
    private let onComplete: (() -> Void)?
    private var elapsed: TimeInterval = 0
    private(set) var isFinished = false

    init(duration: TimeInterval, easing: Easing = .easeInOut,
         tick: @escaping (Double) -> Void,
         onComplete: (() -> Void)? = nil) {
        self.duration = max(duration, 0.0001)
        self.easing = easing
        self.tick = tick
        self.onComplete = onComplete
    }

    func update(dt: TimeInterval) {
        guard !isFinished else { return }
        elapsed += dt
        let t = min(elapsed / duration, 1.0)
        tick(easing.apply(t))
        if t >= 1.0 {
            isFinished = true
            onComplete?()
        }
    }
}

import CoreGraphics
import Foundation

/// Pure math helpers used across the engine. Kept free-function + stateless on purpose so
/// they can be reused by tests, behaviors, commands, and renderers without coupling.

@inlinable func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

@inlinable func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
    a + (b - a) * CGFloat(t)
}

@inlinable func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
    CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
}

/// Exponential smoothing coefficient for a given time constant `tau` (seconds) and `dt`.
/// Use as: `value = lerp(value, target, smooth(dt, tau: 0.2))`.
/// This is frame-rate independent — the same `tau` produces the same perceived easing at
/// any `dt`, which is why cursor-follow feels natural rather than "snappy when fps dips".
@inlinable func smooth(_ dt: TimeInterval, tau: TimeInterval) -> Double {
    1.0 - exp(-dt / max(tau, 1e-4))
}

// MARK: - 2D vector math on CGPoint (treat as vec2)

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { .init(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { .init(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { .init(x: a.x * s, y: a.y * s) }
    static func / (a: CGPoint, s: CGFloat) -> CGPoint { .init(x: a.x / s, y: a.y / s) }
    static func += (a: inout CGPoint, b: CGPoint) { a = a + b }
    static func -= (a: inout CGPoint, b: CGPoint) { a = a - b }

    var length: CGFloat { (x*x + y*y).squareRoot() }
    var lengthSquared: CGFloat { x*x + y*y }

    func normalized() -> CGPoint {
        let l = length
        return l > 1e-6 ? CGPoint(x: x/l, y: y/l) : .zero
    }

    /// Cap the vector's magnitude at `max`. Reynolds' classic steering clamp.
    func truncated(max m: CGFloat) -> CGPoint {
        let l = length
        return l > m && l > 0 ? (self * (m / l)) : self
    }

    func distance(to other: CGPoint) -> CGFloat { (self - other).length }
}

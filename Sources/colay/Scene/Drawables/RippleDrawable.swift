import AppKit
import CoreGraphics

/// Now redesigned into an organic splash/burst matching the new squishy sensing character.
/// It spawns a core pulse and tiny floating glowing droplets, rather than 3 generic flat circles.
final class RippleDrawable: Drawable {
    var tint: NSColor = NSColor(calibratedRed: 0.38, green: 0.86, blue: 1.0, alpha: 1)
    /// 0 = just spawned, 1 = fully expanded + gone.
    var progress: CGFloat = 0
    /// Used by emerge
    var inward: Bool = false

    func draw(in ctx: CGContext, size: CGSize, time: TimeInterval) {
        let maxR = max(size.width, size.height) * 0.4
        if progress <= 0 || progress >= 1 { return }
        
        let p = inward ? (1 - progress) : progress
        // A cubic ease to make the droplet burst snappy
        let e = 1.0 - pow(1.0 - p, 3.0) 
        
        let alpha = (1 - progress) * 0.8
        
        // --- Core Splash Ring ---
        // Rather than a perfect circle, make it squashed slightly like a splash on a surface
        let splashScaleY: CGFloat = 0.4
        ctx.saveGState()
        ctx.scaleBy(x: 1.0, y: splashScaleY)
        
        let r = maxR * e
        let rect = CGRect(x: -r, y: -r, width: r*2, height: r*2)
        ctx.setStrokeColor(tint.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(4.0 * (1-progress))
        ctx.setShadow(offset: .zero, blur: 8, color: tint.withAlphaComponent(0.6).cgColor)
        ctx.strokeEllipse(in: rect)
        ctx.restoreGState()
        
        // --- Flying Droplets (Orbs) ---
        let orbCount = 10
        ctx.saveGState()
        ctx.setFillColor(tint.withAlphaComponent(alpha).cgColor)
        ctx.setShadow(offset: .zero, blur: 6, color: tint.withAlphaComponent(1.0).cgColor)
        
        for i in 0..<orbCount {
            let angle = CGFloat(i) / CGFloat(orbCount) * .pi * 2 + time * 1.5
            // Droplets shoot out way further than the core ring
            let dist = maxR * e * (1.0 + 0.6 * sin(CGFloat(i) * 123.4))
            let orbX = cos(angle) * dist
            // Squish the Y orbit so it looks like it's scattering across the floor plane
            let orbY = sin(angle) * dist * splashScaleY - (e * maxR * 0.3) // also arc upward slightly over time
            
            // Randomly size them
            let rawSize = 2.0 + 3.0 * sin(CGFloat(i) * 45.0 + time * 5)
            let orbSize: CGFloat = max(1.0, rawSize * (1.0 - progress))
            
            ctx.fillEllipse(in: CGRect(x: orbX - orbSize/2, y: orbY - orbSize/2, width: orbSize, height: orbSize))
        }
        ctx.restoreGState()
    }
}

import AppKit
import CoreGraphics

/// Marker drawn around the window the avatar is currently attached to. Visually
/// distinct from `HighlightRectDrawable` (orange, breathing, full rectangle) so the
/// user can tell "character lives here right now" apart from a one-shot highlight:
///
///   • teal / cyan corner brackets (L-shapes) at the four corners, not a full border
///   • gentle pulse that ramps the bracket length + glow
///   • a very faint tinted fill so the window region reads as "occupied"
///
/// Owns nothing beyond its own paint. Its enclosing Node's transform is set to the
/// attached window's bounds; this drawable simply renders into that rect each frame.
final class AttachmentMarkerDrawable: Drawable {
    /// Teal — intentionally far from the orange used by `HighlightRectDrawable`.
    var color: NSColor = NSColor(calibratedRed: 0.22, green: 0.88, blue: 0.82, alpha: 1)
    var lineWidth: CGFloat = 3
    var cornerRadius: CGFloat = 10

    /// Fraction of the shorter side used for the L-bracket arm length (min/max pulse).
    var bracketFracMin: CGFloat = 0.06
    var bracketFracMax: CGFloat = 0.11

    func draw(in ctx: CGContext, size: CGSize, time: TimeInterval) {
        guard size.width > 2, size.height > 2 else { return }

        // Slow pulse (≈ 0.45 Hz) — noticeable but not anxious.
        let pulse = 0.5 + 0.5 * sin(time * 2.8)
        let frac = bracketFracMin + (bracketFracMax - bracketFracMin) * CGFloat(pulse)
        let shortSide = min(size.width, size.height)
        let arm = max(12, shortSide * frac)

        let rect = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2,
                                                             dy: lineWidth / 2)

        // Faint tinted fill — very low alpha so it doesn't fight with the window's
        // own contents, but enough to register in peripheral vision.
        let fillAlpha: CGFloat = 0.05 + 0.03 * CGFloat(pulse)
        ctx.setFillColor(color.withAlphaComponent(fillAlpha).cgColor)
        let fillPath = CGPath(roundedRect: rect,
                              cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                              transform: nil)
        ctx.addPath(fillPath)
        ctx.fillPath()

        // Corner brackets.
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShadow(offset: .zero,
                      blur: 8 + 6 * CGFloat(pulse),
                      color: color.withAlphaComponent(0.9).cgColor)

        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY

        // Each corner: two short strokes forming an L, inset by cornerRadius so the
        // bracket arms follow the rounded-rect silhouette.
        let inset = cornerRadius
        let segments: [(CGPoint, CGPoint)] = [
            // Bottom-left
            (CGPoint(x: minX, y: minY + inset + arm), CGPoint(x: minX, y: minY + inset)),
            (CGPoint(x: minX + inset, y: minY),       CGPoint(x: minX + inset + arm, y: minY)),
            // Bottom-right
            (CGPoint(x: maxX, y: minY + inset + arm), CGPoint(x: maxX, y: minY + inset)),
            (CGPoint(x: maxX - inset, y: minY),       CGPoint(x: maxX - inset - arm, y: minY)),
            // Top-left
            (CGPoint(x: minX, y: maxY - inset - arm), CGPoint(x: minX, y: maxY - inset)),
            (CGPoint(x: minX + inset, y: maxY),       CGPoint(x: minX + inset + arm, y: maxY)),
            // Top-right
            (CGPoint(x: maxX, y: maxY - inset - arm), CGPoint(x: maxX, y: maxY - inset)),
            (CGPoint(x: maxX - inset, y: maxY),       CGPoint(x: maxX - inset - arm, y: maxY)),
        ]
        for (a, b) in segments {
            ctx.move(to: a)
            ctx.addLine(to: b)
        }
        ctx.strokePath()
    }
}

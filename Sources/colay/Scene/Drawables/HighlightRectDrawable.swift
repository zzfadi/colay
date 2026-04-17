import AppKit
import CoreGraphics

/// Animated highlight box that breathes and fades out. Used by HighlightWindowCommand.
final class HighlightRectDrawable: Drawable {
    var color: NSColor = NSColor(calibratedRed: 1, green: 0.78, blue: 0.22, alpha: 1)
    var lineWidth: CGFloat = 3
    var cornerRadius: CGFloat = 10

    /// 0..1 pulse phase; owner advances it externally for sync with fade lifetime.
    var pulse: Double = 0

    func draw(in ctx: CGContext, size: CGSize, time: TimeInterval) {
        let p = 0.5 + 0.5 * sin(time * 4.0)
        let expand = CGFloat(p) * 2
        let r = CGRect(x: -expand, y: -expand,
                       width: size.width + expand*2, height: size.height + expand*2)
        let path = CGPath(roundedRect: r.insetBy(dx: lineWidth/2, dy: lineWidth/2),
                          cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                          transform: nil)
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setShadow(offset: .zero, blur: 10, color: color.withAlphaComponent(0.8).cgColor)
        ctx.strokePath()
    }
}

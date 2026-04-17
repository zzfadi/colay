import CoreGraphics
import Foundation

/// Anything that can paint itself inside a local coordinate frame. The frame is already
/// transformed by the node's Transform before `draw` is called, so drawables draw around
/// the origin.
protocol Drawable: AnyObject {
    func draw(in ctx: CGContext, size: CGSize, time: TimeInterval)
}

/// Carries a Drawable for the Renderer to paint. Separated from Transform so non-visual
/// nodes (pure logic, HUD anchors) can exist without a drawable.
final class RenderComponent: Component {
    var drawable: Drawable
    /// Z-like hint; higher paints on top of lower within the same parent. Stable-sorted.
    var layer: Int = 0

    init(_ drawable: Drawable, layer: Int = 0) {
        self.drawable = drawable
        self.layer = layer
    }
}

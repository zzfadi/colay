import CoreGraphics

/// Position / rotation / scale / alpha. Always attached to every Node.
final class TransformComponent: Component {
    var position: CGPoint = .zero
    var rotation: CGFloat = 0        // radians
    var scale: CGFloat = 1
    var alpha: CGFloat = 1
    var visible: Bool = true
    var size: CGSize = .zero          // logical content size, used by Drawables

    /// Local transform from this node's space into its parent's space.
    var localMatrix: CGAffineTransform {
        var t = CGAffineTransform(translationX: position.x, y: position.y)
        if rotation != 0 { t = t.rotated(by: rotation) }
        if scale != 1 { t = t.scaledBy(x: scale, y: scale) }
        return t
    }
}

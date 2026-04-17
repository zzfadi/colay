import CoreGraphics
import Foundation

/// Depth-first traversal painter. Concatenates transforms, applies alpha, then dispatches
/// to the node's Drawable. Children are sorted by their RenderComponent.layer for a stable
/// back-to-front order per parent.
final class Renderer {
    func render(root: Node, in ctx: CGContext, size: CGSize, time: TimeInterval) {
        ctx.saveGState()
        draw(node: root, ctx: ctx, parent: .identity, parentAlpha: 1, time: time)
        ctx.restoreGState()
    }

    private func draw(node: Node, ctx: CGContext, parent: CGAffineTransform,
                      parentAlpha: CGFloat, time: TimeInterval) {
        let t = node.transform
        guard t.visible, t.alpha > 0 else { return }

        let world = t.localMatrix.concatenating(parent)
        let alpha = parentAlpha * t.alpha

        if let rc = node.component(RenderComponent.self), rc.enabled {
            ctx.saveGState()
            ctx.concatenate(world)
            ctx.setAlpha(alpha)
            rc.drawable.draw(in: ctx, size: t.size, time: time)
            ctx.restoreGState()
        }

        let sorted = node.children.sorted { a, b in
            let la = a.component(RenderComponent.self)?.layer ?? 0
            let lb = b.component(RenderComponent.self)?.layer ?? 0
            return la < lb
        }
        for c in sorted {
            draw(node: c, ctx: ctx, parent: world, parentAlpha: alpha, time: time)
        }
    }
}

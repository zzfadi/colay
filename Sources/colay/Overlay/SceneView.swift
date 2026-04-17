import AppKit
import CoreGraphics

/// Transparent NSView that renders the scene graph via Core Graphics each frame.
/// Owns its Scene so the Engine can swap scenes wholesale if needed (tests, A/B).
final class SceneView: NSView {
    var scene: Scene = Scene()
    var currentTime: TimeInterval = 0

    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)
        scene.render(in: ctx, size: bounds.size, time: currentTime)
    }
}

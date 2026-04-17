import AppKit

/// Full-screen transparent, click-through overlay. Hosts the SceneView and exposes coord
/// conversion to the rest of the engine via `OverlayRef`.
final class OverlayWindowController: NSWindowController, OverlayRef {
    let sceneView: SceneView

    init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false

        let view = SceneView(frame: screenFrame)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        self.sceneView = view

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.orderFrontRegardless()
    }

    func setInteractive(_ interactive: Bool) {
        window?.ignoresMouseEvents = !interactive
    }

    // MARK: - OverlayRef

    var frame: CGRect { window?.frame ?? .zero }
    var size: CGSize { sceneView.bounds.size }

    func localToScreen(_ p: CGPoint) -> CGPoint {
        let f = frame
        return CGPoint(x: f.origin.x + p.x, y: f.origin.y + p.y)
    }

    /// AX returns top-left origin global screen coords. Convert to bottom-left overlay-local.
    func screenRectToLocal(_ r: CGRect) -> CGRect {
        let screenHeight = NSScreen.screens.first?.frame.height ?? frame.height
        let f = frame
        let localX = r.origin.x - f.origin.x
        let localY = (screenHeight - r.origin.y - r.height) - f.origin.y
        return CGRect(x: localX, y: localY, width: r.width, height: r.height)
    }
}

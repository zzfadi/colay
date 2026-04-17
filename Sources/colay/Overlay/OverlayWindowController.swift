import AppKit

/// Full-screen transparent, click-through overlay. Hosts the SceneView and exposes coord
/// conversion to the rest of the engine via `OverlayRef`.
///
/// The overlay spans the *union of all connected displays* so the character can roam
/// across multi-monitor setups and dive into windows on any screen. Its origin sits at
/// `NSScreen.screens` global origin (bottom-left of the primary display in Cocoa coords,
/// possibly negative if auxiliary monitors extend left or below).
final class OverlayWindowController: NSWindowController, OverlayRef {
    let sceneView: SceneView

    /// Returns the Cocoa-coord union of every connected display. Falls back to the main
    /// screen, then to a safe default if called during unusual startup conditions.
    private static func unionOfAllScreens() -> NSRect {
        let screens = NSScreen.screens
        guard let first = screens.first else {
            return NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        }
        return screens.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    init() {
        let screenFrame = Self.unionOfAllScreens()
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

    /// AX returns top-left origin global screen coords where Y is measured from the top
    /// of the **primary** display (the one whose Cocoa frame origin is (0, 0)). We use
    /// that specific display's height to flip Y into Cocoa (bottom-left origin) space,
    /// then subtract the overlay's Cocoa origin to land in overlay-local coords. This
    /// works correctly when secondary displays are arranged above / beside the primary.
    func screenRectToLocal(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? frame.height
        let f = frame
        let localX = r.origin.x - f.origin.x
        let localY = (primaryHeight - r.origin.y - r.height) - f.origin.y
        return CGRect(x: localX, y: localY, width: r.width, height: r.height)
    }
}

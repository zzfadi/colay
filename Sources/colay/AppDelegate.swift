import AppKit

/// Thin AppKit shell. Owns the overlay window, the engine, and the status-bar controller,
/// and wires their callbacks. All real logic lives in the Engine + Commands layers.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayWindowController!
    private var engine: Engine!
    private var status: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayWindowController()
        overlay.showWindow(nil)

        engine = Engine(overlay: overlay)
        engine.start()

        status = StatusItemController(
            registry: engine.registry,
            scheduler: engine.scheduler,
            services: engine.makeServices()
        )
        status.onOpenScript = { [weak self] in self?.openScript() }
        status.onRunDemo = { [weak self] in
            if let url = self?.demoURL() { self?.engine.loadScript(at: url) }
        }
        status.onTogglePause = { [weak self] in self?.engine.togglePause() }
        status.onToggleSlowMo = { [weak self] in self?.engine.toggleSlowMo() }
    }

    private func demoURL() -> URL? {
        Bundle.module.url(forResource: "demo", withExtension: "json")
    }

    private func openScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            engine.loadScript(at: url)
        }
    }
}

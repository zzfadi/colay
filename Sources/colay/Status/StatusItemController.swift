import AppKit
import CoreGraphics
import Foundation

// MARK: - Status bar controller
//
// The status bar item is a tiny "LED" icon. Clicking it toggles a *dashboard popover*
// instead of a menu — it's a full custom view with cards, pill buttons, and live stats.
// The popover is the primary UI surface during development; the menu metaphor was
// fighting what we actually want to render.

/// Thin public API hosted by `AppDelegate`. The controller owns the status item, the
/// icon animator, and the popover.
final class StatusItemController: NSObject {

    // Injected deps.
    private let registry: CommandRegistry
    private let scheduler: CommandScheduler
    private let services: Services

    // Views / system objects.
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let dashboard: DashboardViewController

    // Icon animator.
    private var iconTimer: Timer?
    private var iconPhase: TimeInterval = 0

    // Exposed callbacks.
    var onOpenScript: (() -> Void)?
    var onRunDemo: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onToggleSlowMo: (() -> Void)?

    init(registry: CommandRegistry, scheduler: CommandScheduler, services: Services) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: 28)
        self.registry = registry
        self.scheduler = scheduler
        self.services = services
        self.dashboard = DashboardViewController(services: services, scheduler: scheduler)
        super.init()

        configureStatusItem()
        configurePopover()
        wireDashboardCallbacks()

        iconTimer = Timer.scheduledTimer(withTimeInterval: 1.0/8.0, repeats: true) { [weak self] _ in
            self?.tickIcon()
        }
        RunLoop.main.add(iconTimer!, forMode: .common)
    }

    deinit {
        iconTimer?.invalidate()
    }

    // MARK: - Setup

    private func configureStatusItem() {
        statusItem.button?.image = drawIcon(eyeLook: 0, talking: false)
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient      // auto-dismiss when user clicks elsewhere
        popover.animates = true
        popover.contentViewController = dashboard
        popover.contentSize = NSSize(width: 320, height: 560)
    }

    private func wireDashboardCallbacks() {
        dashboard.onOpenScript = { [weak self] in self?.onOpenScript?() }
        dashboard.onRunDemo = { [weak self] in self?.onRunDemo?() }
        dashboard.onTogglePause = { [weak self] in self?.onTogglePause?() }
        dashboard.onToggleSlowMo = { [weak self] in self?.onToggleSlowMo?() }
        dashboard.onQuit = { NSApp.terminate(nil) }
    }

    // MARK: - Popover toggle

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Focus the popover's window so keyboard shortcuts inside it work.
        popover.contentViewController?.view.window?.makeKey()
        dashboard.didAppear()
    }

    // MARK: - Icon animator

    private func tickIcon() {
        iconPhase += 0.12
        let look = CGFloat(sin(iconPhase * 0.6))
        let talking = scheduler.isRunning // pulse icon while commands run
        statusItem.button?.image = drawIcon(eyeLook: look, talking: talking)
        statusItem.button?.image?.isTemplate = true
    }

    /// A tiny menubar-safe line drawing of the character. Template-rendered so macOS tints
    /// it for light/dark mode.
    private func drawIcon(eyeLook: CGFloat, talking: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return img }

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1.3)

        let bodyW = 12.0 + 0.6 * sin(iconPhase * 2.0)
        let bodyH = 11.0 - 0.6 * sin(iconPhase * 2.0)
        let rect = CGRect(x: (size.width - bodyW)/2,
                          y: (size.height - bodyH)/2 - 1,
                          width: bodyW, height: bodyH)
        let corner = bodyW * 0.45
        let body = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner,
                          transform: nil)

        ctx.addPath(body)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        // Eyes with live look direction.
        let eyeY = rect.midY
        let off = eyeLook * 1.4
        ctx.fillEllipse(in: CGRect(x: rect.midX - 2.6 + off, y: eyeY - 1, width: 2, height: 2))
        ctx.fillEllipse(in: CGRect(x: rect.midX + 0.6 + off, y: eyeY - 1, width: 2, height: 2))

        // Little "busy" indicator — an antenna that pulses while commands are running.
        let antY = rect.maxY + 2 + CGFloat(sin(iconPhase * 4) * (talking ? 2.5 : 1.0))
        let antR: CGFloat = talking ? 2.4 : 1.6
        ctx.fillEllipse(in: CGRect(x: rect.midX - antR/2, y: antY,
                                   width: antR, height: antR))

        return img
    }
}

private extension CommandScheduler {
    /// Convenience for UI — is there a sequence command, background command, or queued work?
    var isRunning: Bool {
        !sequence.isEmpty
    }
}

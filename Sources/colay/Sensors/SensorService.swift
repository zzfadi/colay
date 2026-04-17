import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Immutable snapshot of the focused window. Passed as an Event on the bus.
struct FocusedWindowInfo: Event {
    let pid: pid_t
    let appName: String?
    let windowTitle: String?
    let bounds: CGRect?            // in screen coords, top-left origin (as AX returns)
    let axWindow: AXUIElement?     // retained AX handle; nil when probe failed
    let timestamp: TimeInterval

    var debugDescription: String {
        let b = bounds.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "nil"
        return "pid=\(pid) app=\(appName ?? "?") title=\(windowTitle ?? "?") bounds=\(b)"
    }
}

/// Event-driven sensor service.
///
/// Old implementation polled AX synchronously every frame — that's what was locking the
/// UI. Here's the fix:
///
/// 1. We listen to `NSWorkspace.didActivateApplicationNotification` (cheap, OS-delivered)
///    to know when the frontmost app changes.
/// 2. For the focused *window* within an app, there's no free notification, so we
///    **debounce** AX queries behind a min interval AND only run them if someone
///    subscribed to FocusedWindowInfo on the bus.
/// 3. All AX calls are **dispatched to a utility queue** so if an unresponsive app
///    blocks AX, the main thread (render loop) is never stalled.
/// 4. Results are delivered back on main via the EventBus. A private cache is also kept
///    so one-shot commands (`captureFocusedWindow`) can hit the last known value
///    immediately without re-querying.
///
/// Public API surface is tiny — consumers either subscribe via the bus or call
/// `requestFocusedWindowSnapshot` for one-off.
final class SensorService {
    private let bus: EventBus
    private let queue = DispatchQueue(label: "colay.sensor", qos: .utility)

    /// Minimum seconds between two AX probes of the focused window.
    var minProbeInterval: TimeInterval = 0.25

    private var lastProbe: TimeInterval = 0
    private var lastInfo: FocusedWindowInfo?
    private var workspaceObserver: NSObjectProtocol?

    init(bus: EventBus) {
        self.bus = bus
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleProbe(force: true)
        }
    }

    deinit {
        if let o = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
    }

    /// Called once per frame by the Engine. Cheap — only actually probes if throttling
    /// allows AND somebody is subscribed. This is what makes the service essentially free
    /// when idle.
    func frameTick(now: TimeInterval) {
        guard bus.subscriberCount(FocusedWindowInfo.self) > 0 else { return }
        if now - lastProbe >= minProbeInterval {
            lastProbe = now
            scheduleProbe(force: false)
        }
    }

    /// One-shot request. Runs on the sensor queue, returns on main. Does NOT require a
    /// subscriber on the bus. Used by commands like `captureFocusedWindow`.
    func requestFocusedWindowSnapshot(_ completion: @escaping (FocusedWindowInfo) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let info = self.probeSync()
            DispatchQueue.main.async {
                self.lastInfo = info
                completion(info)
            }
        }
    }

    /// Last cached value (main-thread only).
    var cachedFocusedWindow: FocusedWindowInfo? { lastInfo }

    // MARK: - Private

    private func scheduleProbe(force: Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let info = self.probeSync()
            DispatchQueue.main.async {
                // Only publish if something changed, to avoid waking up subscribers for
                // nothing. Publish always on forced probes (first call after app switch).
                let changed = self.didChange(self.lastInfo, info)
                self.lastInfo = info
                if force || changed {
                    self.bus.publish(info)
                }
            }
        }
    }

    private func didChange(_ old: FocusedWindowInfo?, _ new: FocusedWindowInfo) -> Bool {
        guard let old = old else { return true }
        if old.pid != new.pid || old.windowTitle != new.windowTitle { return true }
        if (old.bounds ?? .zero) != (new.bounds ?? .zero) { return true }
        return false
    }

    /// Synchronous AX probe. Runs on `queue`, never on main.
    private func probeSync() -> FocusedWindowInfo {
        let ts = CFAbsoluteTimeGetCurrent()
        let app = NSWorkspace.shared.frontmostApplication
        guard let pid = app?.processIdentifier else {
            return FocusedWindowInfo(pid: 0, appName: nil, windowTitle: nil,
                                     bounds: nil, axWindow: nil, timestamp: ts)
        }
        let axApp = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref)
        guard err == .success, let v = ref else {
            return FocusedWindowInfo(pid: pid, appName: app?.localizedName,
                                     windowTitle: nil, bounds: nil,
                                     axWindow: nil, timestamp: ts)
        }
        let window = v as! AXUIElement

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var bounds: CGRect? = nil
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
           AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success {
            var p = CGPoint.zero
            var s = CGSize.zero
            AXValueGetValue(posRef as! AXValue, .cgPoint, &p)
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &s)
            bounds = CGRect(origin: p, size: s)
        }
        return FocusedWindowInfo(pid: pid, appName: app?.localizedName,
                                 windowTitle: title, bounds: bounds,
                                 axWindow: window, timestamp: ts)
    }
}

import ApplicationServices
import CoreGraphics
import Foundation

/// Stable handle to a window the avatar is currently "inside" or operating on. Kept as
/// a value type so components/commands can copy it without worrying about mutation.
///
/// `axWindow` is the real control surface — any future commands (click a button inside,
/// read text, wait for title change) should go through this, not re-query the focused
/// window every time. The bounds are a cached snapshot-at-attach for visuals; they will
/// drift if the user moves the window, so refresh before using them for click math.
struct WindowTarget {
    let pid: pid_t
    let appName: String?
    let title: String?
    let bounds: CGRect          // screen coords, top-left origin, captured at attach time
    let axWindow: AXUIElement?  // nil when created in a test/preview context
    let attachedAt: TimeInterval
}

/// State-only component: "is the avatar currently attached to a window, and if so, which?"
/// Intentionally separate from any visual effect so commands that *move* the character
/// into/out of a window and commands that *operate* on the attached window are
/// independent concerns.
///
/// - `target == nil` → free-roaming
/// - `target != nil` → attached; future AI tool calls should read from this
final class WindowAttachmentComponent: Component {
    private(set) var target: WindowTarget?

    func attach(_ t: WindowTarget) { target = t }
    func detach() { target = nil }
    var isAttached: Bool { target != nil }
}

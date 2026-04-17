import ApplicationServices
import AppKit
import Foundation

/// Accessibility permission is required for two things in colay:
///   1. `SensorService` AX probes of the focused window (title/bounds)
///   2. `InputSynth` posting synthesized mouse clicks and keystrokes
///
/// Without it, the character still draws and tracks the cursor, but "Dive In",
/// "Highlight", "Snapshot", `click`, and `type` all silently no-op. Rather than let the
/// user discover this via broken buttons, we prompt once at launch.
enum AccessibilityPermission {
    /// Returns true if the app is already trusted. If `prompt` is true and we are not
    /// trusted, macOS will pop the standard "open System Settings" dialog.
    @discardableResult
    static func ensureTrusted(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Cheap, non-prompting status check — safe to poll from UI.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }
}

import AppKit
import CoreGraphics
import Foundation

/// Synthesizes mouse/keyboard events via CGEvent. Requires Accessibility permission.
final class InputSynth {
    func click(at screenPoint: CGPoint, button: String) {
        // CGEvent uses top-left origin; NSEvent-style coords are bottom-left.
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let p = CGPoint(x: screenPoint.x, y: screenHeight - screenPoint.y)

        let (down, up, mb): (CGEventType, CGEventType, CGMouseButton)
        switch button.lowercased() {
        case "right": (down, up, mb) = (.rightMouseDown, .rightMouseUp, .right)
        case "middle", "other": (down, up, mb) = (.otherMouseDown, .otherMouseUp, .center)
        default: (down, up, mb) = (.leftMouseDown, .leftMouseUp, .left)
        }

        // Move cursor first
        if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                              mouseCursorPosition: p, mouseButton: mb) {
            move.post(tap: .cghidEventTap)
        }
        if let d = CGEvent(mouseEventSource: nil, mouseType: down,
                           mouseCursorPosition: p, mouseButton: mb) {
            d.post(tap: .cghidEventTap)
        }
        if let u = CGEvent(mouseEventSource: nil, mouseType: up,
                           mouseCursorPosition: p, mouseButton: mb) {
            u.post(tap: .cghidEventTap)
        }
    }

    func typeCharacter(_ ch: Character) {
        let str = String(ch)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return }
        let utf16 = Array(str.utf16)
        utf16.withUnsafeBufferPointer { buf in
            down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

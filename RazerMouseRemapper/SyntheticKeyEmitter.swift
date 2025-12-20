import CoreGraphics
import Foundation

/// Emits synthetic keyboard events via CGEvent
final class SyntheticKeyEmitter {

    /// CGKeyCode mapping for F1-F12 keys
    static let fKeyCodes: [Int: CGKeyCode] = [
        1: 122,   // F1
        2: 120,   // F2
        3: 99,    // F3
        4: 118,   // F4
        5: 96,    // F5
        6: 97,    // F6
        7: 98,    // F7
        8: 100,   // F8
        9: 101,   // F9
        10: 109,  // F10
        11: 103,  // F11
        12: 111   // F12
    ]

    /// Posts a synthetic key event
    /// - Parameters:
    ///   - keyCode: The CGKeyCode to post
    ///   - keyDown: true for key down, false for key up
    func postKeyEvent(keyCode: CGKeyCode, keyDown: Bool) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: keyDown
        ) else {
            print("[SyntheticKeyEmitter] Failed to create keyboard event for keyCode: \(keyCode)")
            return
        }

        event.post(tap: .cghidEventTap)
    }

    /// Posts a synthetic F-key event
    /// - Parameters:
    ///   - fKeyNumber: The F-key number (1-12)
    ///   - keyDown: true for key down, false for key up
    func postFKey(number: Int, keyDown: Bool) {
        guard let keyCode = Self.fKeyCodes[number] else {
            print("[SyntheticKeyEmitter] Invalid F-key number: \(number)")
            return
        }

        postKeyEvent(keyCode: keyCode, keyDown: keyDown)
    }
}

import Foundation
import IOKit.hid

/// Handles HID input and remaps number keys to F-keys
final class KeyRemapper {

    /// HID Usage codes for number row keys (keyboard usage page 0x07)
    /// These are the USB HID usage codes, not CGKeyCodes
    static let numberKeyUsages: [UInt32: Int] = [
        0x1E: 1,   // Key "1" -> F1
        0x1F: 2,   // Key "2" -> F2
        0x20: 3,   // Key "3" -> F3
        0x21: 4,   // Key "4" -> F4
        0x22: 5,   // Key "5" -> F5
        0x23: 6,   // Key "6" -> F6
        0x24: 7,   // Key "7" -> F7
        0x25: 8,   // Key "8" -> F8
        0x26: 9,   // Key "9" -> F9
        0x27: 10,  // Key "0" -> F10
        0x2D: 11,  // Key "-" -> F11
        0x2E: 12   // Key "=" -> F12
    ]

    private let keyEmitter = SyntheticKeyEmitter()

    /// Enabled state - when false, no remapping occurs
    var isEnabled: Bool = false

    /// Debug mode - logs all HID values
    var debugMode: Bool = true

    /// Process an HID input value and emit remapped key if applicable
    /// - Parameter value: The IOHIDValue from the HID device
    /// - Returns: true if the key was remapped, false otherwise
    @discardableResult
    func processHIDValue(_ value: IOHIDValue) -> Bool {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        // Debug logging for all HID values
        if debugMode && intValue != 0 {
            print("[KeyRemapper DEBUG] UsagePage: 0x\(String(usagePage, radix: 16)), Usage: 0x\(String(usage, radix: 16)), Value: \(intValue)")
        }

        guard isEnabled else { return false }

        // Process keyboard usage page (0x07)
        if usagePage == 0x07 {
            if let fKeyNumber = Self.numberKeyUsages[UInt32(usage)] {
                let isKeyDown = intValue != 0
                keyEmitter.postFKey(number: fKeyNumber, keyDown: isKeyDown)
                print("[KeyRemapper] Remapped key usage 0x\(String(usage, radix: 16)) -> F\(fKeyNumber) (\(isKeyDown ? "down" : "up"))")
                return true
            }
        }

        return false
    }
}

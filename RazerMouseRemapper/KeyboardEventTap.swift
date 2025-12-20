import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Intercepts keyboard events using CGEventTap and remaps number keys to F-keys
/// Only remaps keys that were recently detected from the Razer mouse via HID
final class KeyboardEventTap {

    /// Key code mapping: number row keys to F-keys
    /// These are macOS virtual key codes (not HID usage codes)
    static let keyRemapping: [CGKeyCode: CGKeyCode] = [
        18: 122,   // 1 -> F1
        19: 120,   // 2 -> F2
        20: 99,    // 3 -> F3
        21: 118,   // 4 -> F4
        23: 96,    // 5 -> F5
        22: 97,    // 6 -> F6
        26: 98,    // 7 -> F7
        28: 100,   // 8 -> F8
        25: 101,   // 9 -> F9
        29: 109,   // 0 -> F10
        27: 103,   // - -> F11
        24: 111    // = -> F12
    ]

    /// HID usage to CGKeyCode mapping (for correlation)
    /// HID usages from keyboard page (0x07) to macOS key codes
    static let hidUsageToCGKeyCode: [UInt32: CGKeyCode] = [
        0x1E: 18,   // Key "1"
        0x1F: 19,   // Key "2"
        0x20: 20,   // Key "3"
        0x21: 21,   // Key "4"
        0x22: 23,   // Key "5"
        0x23: 22,   // Key "6"
        0x24: 26,   // Key "7"
        0x25: 28,   // Key "8"
        0x26: 25,   // Key "9"
        0x27: 29,   // Key "0"
        0x2D: 27,   // Key "-"
        0x2E: 24    // Key "="
    ]

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Keys currently held down from mouse (based on HID events)
    private var activeMouseKeys: Set<CGKeyCode> = []
    /// Keys that were remapped on keyDown and need their keyUp remapped too
    private var remappedKeys: Set<CGKeyCode> = []
    private let keyLock = NSLock()

    var isEnabled: Bool = false

    /// Mark a key as active (called when HID key-down from mouse is detected)
    /// - Parameter hidUsage: The HID usage code from keyboard page
    func markKeyActive(hidUsage: UInt32) {
        guard let cgKeyCode = Self.hidUsageToCGKeyCode[hidUsage] else { return }

        keyLock.lock()
        activeMouseKeys.insert(cgKeyCode)
        keyLock.unlock()

        debugLog("Marked key \(cgKeyCode) as ACTIVE from HID usage 0x\(String(hidUsage, radix: 16))")
    }

    /// Mark a key as inactive (called when HID key-up from mouse is detected)
    /// - Parameter hidUsage: The HID usage code from keyboard page
    func markKeyInactive(hidUsage: UInt32) {
        guard let cgKeyCode = Self.hidUsageToCGKeyCode[hidUsage] else { return }

        keyLock.lock()
        activeMouseKeys.remove(cgKeyCode)
        keyLock.unlock()

        debugLog("Marked key \(cgKeyCode) as INACTIVE from HID usage 0x\(String(hidUsage, radix: 16))")
    }

    private func debugLog(_ message: String) {
        let logFile = "/tmp/razer-remapper.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [EventTap] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let handle = FileHandle(forWritingAtPath: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logFile, contents: data)
            }
        }
    }

    /// Check if a key should be remapped on keyDown
    private func shouldRemapKeyDown(_ keyCode: CGKeyCode) -> Bool {
        keyLock.lock()
        let isActive = activeMouseKeys.contains(keyCode)
        if isActive {
            remappedKeys.insert(keyCode)
        }
        keyLock.unlock()
        return isActive
    }

    /// Check if a key should be remapped on keyUp
    private func shouldRemapKeyUp(_ keyCode: CGKeyCode) -> Bool {
        keyLock.lock()
        let wasRemapped = remappedKeys.contains(keyCode)
        if wasRemapped {
            remappedKeys.remove(keyCode)
        }
        keyLock.unlock()
        return wasRemapped
    }

    /// Start intercepting keyboard events
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // Create event tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let tap = Unmanaged<KeyboardEventTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[KeyboardEventTap] Failed to create event tap - need Accessibility permission")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        NSLog("[KeyboardEventTap] Started")
        return true
    }

    /// Stop intercepting keyboard events
    func stop() {
        guard let tap = eventTap else { return }

        CGEvent.tapEnable(tap: tap, enable: false)

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        eventTap = nil
        NSLog("[KeyboardEventTap] Stopped")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled event (system can disable tap if it's too slow)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard isEnabled else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isKeyDown = type == .keyDown

        // Check if this is a key we could remap
        if let newKeyCode = Self.keyRemapping[keyCode] {
            debugLog("CGEvent: keyCode=\(keyCode) isKeyDown=\(isKeyDown)")

            let shouldRemap: Bool
            if isKeyDown {
                // On keyDown: remap if key is active from mouse, and track it
                shouldRemap = shouldRemapKeyDown(keyCode)
            } else {
                // On keyUp: remap if we remapped the corresponding keyDown
                shouldRemap = shouldRemapKeyUp(keyCode)
            }

            if shouldRemap {
                event.setIntegerValueField(.keyboardEventKeycode, value: Int64(newKeyCode))
                debugLog("REMAPPED key \(keyCode) -> \(newKeyCode) (\(isKeyDown ? "down" : "up"))")
            } else {
                debugLog("Key \(keyCode) not from mouse, passing through")
            }
        }

        return Unmanaged.passRetained(event)
    }

    deinit {
        stop()
    }
}

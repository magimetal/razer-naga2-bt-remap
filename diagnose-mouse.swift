#!/usr/bin/env swift
// Diagnostic script to monitor Razer mouse HID events
// Run with: swift diagnose-mouse.swift

import Foundation
import IOKit.hid
import CoreGraphics

// Force unbuffered output
setbuf(stdout, nil)
setbuf(stderr, nil)

// ========== Configuration ==========
let razerVendorIDs: [Int] = [0x1532, 1678]  // USB and Bluetooth Razer

// ========== HID Monitoring ==========
var hidManager: IOHIDManager?

func log(_ msg: String) {
    let timestamp = Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    print("[\(formatter.string(from: timestamp))] \(msg)")
    fflush(stdout)
}

func startHIDMonitoring() -> Bool {
    log("Creating HID Manager...")

    hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    guard let manager = hidManager else {
        log("❌ Failed to create IOHIDManager")
        return false
    }

    // Match all Razer devices
    var matchingDicts: [[String: Any]] = []
    for vendorID in razerVendorIDs {
        matchingDicts.append([kIOHIDVendorIDKey as String: vendorID])
    }
    IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts as CFArray)

    // Device callbacks
    let deviceMatchCallback: IOHIDDeviceCallback = { context, result, sender, device in
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        log("✅ Device connected: \(name) (VID: 0x\(String(vid, radix: 16)), PID: 0x\(String(pid, radix: 16)))")

        // Register input callback for this device
        IOHIDDeviceRegisterInputValueCallback(device, { context, result, sender, value in
            let element = IOHIDValueGetElement(value)
            let usagePage = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let intValue = IOHIDValueGetIntegerValue(value)

            // Only log non-zero values or button releases
            if intValue != 0 || usagePage == 0x09 {
                let pageName = getUsagePageName(usagePage)
                let usageName = getUsageName(usagePage: usagePage, usage: usage)
                log("🔵 HID: Page=\(pageName)(0x\(String(usagePage, radix: 16))) Usage=\(usageName)(0x\(String(usage, radix: 16))) Val=\(intValue)")
            }
        }, nil)
    }

    IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchCallback, nil)

    log("Scheduling on run loop...")
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

    log("Opening HID manager...")
    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    if result != kIOReturnSuccess {
        log("❌ Failed to open HID manager: \(result)")
        return false
    }

    log("🎮 HID monitoring started!")
    return true
}

// ========== CGEvent Monitoring ==========
var eventTap: CFMachPort?

func startCGEventMonitoring() -> Bool {
    log("Creating CGEvent tap...")

    // Monitor keyboard AND mouse button events
    let eventMask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue) |
        (1 << CGEventType.keyUp.rawValue) |
        (1 << CGEventType.otherMouseDown.rawValue) |
        (1 << CGEventType.otherMouseUp.rawValue)

    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: eventMask,
        callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            switch type {
            case .keyDown, .keyUp:
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let isDown = type == .keyDown
                log("⌨️ Key: code=\(keyCode) (\(keyCodeName(Int(keyCode)))) \(isDown ? "DOWN" : "UP")")
            case .otherMouseDown, .otherMouseUp:
                let button = event.getIntegerValueField(.mouseEventButtonNumber)
                let isDown = type == .otherMouseDown
                log("🖱️ Mouse: button=\(button) \(isDown ? "DOWN" : "UP")")
            default:
                break
            }
            return Unmanaged.passRetained(event)
        },
        userInfo: nil
    ) else {
        log("❌ CGEvent tap FAILED - need Accessibility permission!")
        log("   System Settings > Privacy & Security > Accessibility")
        return false
    }

    eventTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    log("⌨️ CGEvent tap started!")
    return true
}

// ========== Helper Functions ==========
func getUsagePageName(_ page: UInt32) -> String {
    switch page {
    case 0x01: return "Desktop"
    case 0x07: return "Keyboard"
    case 0x09: return "Button"
    case 0x0C: return "Consumer"
    case 0xFF00...0xFFFF: return "Vendor"
    default: return "Unk"
    }
}

func getUsageName(usagePage: UInt32, usage: UInt32) -> String {
    switch usagePage {
    case 0x01:  // Generic Desktop
        switch usage {
        case 0x30: return "X"
        case 0x31: return "Y"
        case 0x38: return "Wheel"
        default: return "\(usage)"
        }
    case 0x07:  // Keyboard
        if usage >= 0x1E && usage <= 0x27 {
            let num = usage == 0x27 ? 0 : usage - 0x1E + 1
            return "Key\(num)"
        } else if usage >= 0x3A && usage <= 0x45 {
            return "F\(usage - 0x3A + 1)"
        }
        return "\(usage)"
    case 0x09:  // Button
        return "Btn\(usage)"
    default:
        return "\(usage)"
    }
}

func keyCodeName(_ keyCode: Int) -> String {
    let names: [Int: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
    return names[keyCode] ?? "code\(keyCode)"
}

// ========== Main ==========
log("═══════════════════════════════════════════════════════")
log("  RAZER MOUSE DIAGNOSTIC TOOL")
log("═══════════════════════════════════════════════════════")
log("")
log("Monitoring BOTH:")
log("  🔵 HID events (raw device input)")
log("  ⌨️  CGEvents (system-level events)")
log("")
log("Press mouse side buttons to see what they send.")
log("Press Ctrl+C to exit.")
log("")
log("═══════════════════════════════════════════════════════")

let hidOK = startHIDMonitoring()
let cgOK = startCGEventMonitoring()

if !hidOK && !cgOK {
    log("❌ Both monitoring methods failed!")
    exit(1)
}

log("")
log("👆 Ready! Press mouse buttons now...")
log("")

// Keep running
RunLoop.main.run()

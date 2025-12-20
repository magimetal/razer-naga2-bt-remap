import Foundation
import IOKit.hid
import AppKit

/// Manages Input Monitoring permission
struct PermissionManager {

    /// Check if app has Input Monitoring permission by attempting to open HID manager
    static func checkInputMonitoring() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return result == kIOReturnSuccess
    }

    /// Open System Settings to Input Monitoring pane
    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}

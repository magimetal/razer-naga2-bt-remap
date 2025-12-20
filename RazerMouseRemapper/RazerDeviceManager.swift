import Foundation
import IOKit.hid

/// Manages detection and input capture from Razer HID devices
final class RazerDeviceManager {

    /// Razer Vendor IDs
    /// 0x1532 = Razer USB devices
    /// 1678 (0x68E) = Razer Bluetooth devices (Naga V2 HS)
    static let razerVendorIDs: [Int] = [0x1532, 1678]

    /// Singleton instance
    static let shared = RazerDeviceManager()

    /// Callbacks
    var onDeviceConnected: ((String) -> Void)?
    var onDeviceDisconnected: (() -> Void)?
    var onInputValue: ((IOHIDValue) -> Void)?

    /// Current state
    private(set) var isRunning = false
    private(set) var connectedDeviceName: String?

    private var hidManager: IOHIDManager?
    private var connectedDevices: Set<IOHIDDevice> = []

    private init() {}

    /// Start monitoring for Razer devices
    func start() {
        guard !isRunning else { return }

        // Create HID Manager
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            print("[RazerDeviceManager] Failed to create IOHIDManager")
            return
        }

        // Create multiple matching dictionaries for different Razer devices
        // Match by vendor ID only - we'll filter by product name containing "Naga"
        var matchingDicts: [[String: Any]] = []

        for vendorID in Self.razerVendorIDs {
            // Match any device from this vendor (mouse, keyboard, consumer control)
            matchingDicts.append([
                kIOHIDVendorIDKey as String: vendorID
            ])
        }

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts as CFArray)

        // Register device callbacks using the context pointer pattern
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let manager = Unmanaged<RazerDeviceManager>.fromOpaque(context).takeUnretainedValue()
            manager.deviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let manager = Unmanaged<RazerDeviceManager>.fromOpaque(context).takeUnretainedValue()
            manager.deviceDisconnected(device)
        }, context)

        // Register input callback at manager level (receives events from all matched devices)
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            guard let context = context else { return }
            let manager = Unmanaged<RazerDeviceManager>.fromOpaque(context).takeUnretainedValue()
            manager.handleInputValue(value)
        }, context)

        // Schedule on run loop (use commonModes for SwiftUI compatibility)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        // Open the manager in monitor-only mode (don't seize)
        // We use CGEventTap to intercept and remap keys - HID is just for device detection
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            NSLog("[RazerDeviceManager] Failed to open HID manager: \(result)")
            return
        }

        isRunning = true
        NSLog("[RazerDeviceManager] Started monitoring for Razer devices")
    }

    /// Stop monitoring for Razer devices
    func stop() {
        guard isRunning, let manager = hidManager else { return }

        // Unregister callbacks
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)

        // Unschedule and close
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        connectedDevices.removeAll()
        connectedDeviceName = nil
        hidManager = nil
        isRunning = false

        print("[RazerDeviceManager] Stopped monitoring")
    }

    // MARK: - Device Callbacks

    private func deviceConnected(_ device: IOHIDDevice) {
        guard !connectedDevices.contains(device) else { return }

        connectedDevices.insert(device)

        // Get device info
        let name = getDeviceName(device)
        let info = getDeviceInfo(device)
        connectedDeviceName = name

        NSLog("[RazerDeviceManager] Device connected: \(info)")

        // Notify
        DispatchQueue.main.async { [weak self] in
            self?.onDeviceConnected?(name)
        }
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        guard connectedDevices.contains(device) else { return }

        connectedDevices.remove(device)

        let name = getDeviceName(device)
        print("[RazerDeviceManager] Device disconnected: \(name)")

        // Update connected device name
        if let firstDevice = connectedDevices.first {
            connectedDeviceName = getDeviceName(firstDevice)
        } else {
            connectedDeviceName = nil
        }

        // Notify
        DispatchQueue.main.async { [weak self] in
            self?.onDeviceDisconnected?()
        }
    }

    private func handleInputValue(_ value: IOHIDValue) {
        // Debug: log to file
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        if usagePage == 0x07 || usagePage == 0x09 {  // Keyboard or Button page
            debugLog("handleInputValue: page=0x\(String(usagePage, radix: 16)) usage=0x\(String(usage, radix: 16)) val=\(intValue)")
        }

        onInputValue?(value)
    }

    private func debugLog(_ message: String) {
        let logFile = "/tmp/razer-remapper.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [DeviceMgr] \(message)\n"
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

    // MARK: - Helpers

    private func getDeviceName(_ device: IOHIDDevice) -> String {
        if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
            return name
        }
        return "Unknown Razer Device"
    }

    /// Get device info for debugging
    func getDeviceInfo(_ device: IOHIDDevice) -> String {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        return "\(name) (VID: 0x\(String(vid, radix: 16)), PID: 0x\(String(pid, radix: 16)))"
    }
}

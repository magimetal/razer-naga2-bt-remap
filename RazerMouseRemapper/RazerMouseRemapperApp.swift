import SwiftUI
import IOKit.hid

@main
struct RazerMouseRemapperApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.isEnabled ? "gamecontroller.fill" : "gamecontroller")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Central app state management
final class AppState: ObservableObject {
    static let shared = AppState()

    @AppStorage("isEnabled") var isEnabled: Bool = false {
        didSet {
            updateRemappingState()
        }
    }

    @Published var hasInputMonitoringPermission: Bool = false
    @Published var isDeviceConnected: Bool = false
    @Published var connectedDeviceName: String?

    private let deviceManager = RazerDeviceManager.shared
    private let keyboardEventTap = KeyboardEventTap()

    private init() {
        setupDeviceCallbacks()
        checkInputMonitoringPermission()

        // Always try to start monitoring for device detection
        // (remapping only happens if isEnabled)
        startMonitoring()

        // Start event tap if remapping was already enabled (from previous session)
        if isEnabled {
            updateRemappingState()
        }
    }

    private func setupDeviceCallbacks() {
        deviceManager.onDeviceConnected = { [weak self] name in
            self?.isDeviceConnected = true
            self?.connectedDeviceName = name
            // If we can detect devices, we have permission
            self?.hasInputMonitoringPermission = true
            self?.debugLog("Device connected: \(name)")
        }

        deviceManager.onDeviceDisconnected = { [weak self] in
            self?.isDeviceConnected = self?.deviceManager.connectedDeviceName != nil
            self?.connectedDeviceName = self?.deviceManager.connectedDeviceName
            print("[AppState] Device disconnected")
        }

        // Wire up HID input to mark keys as pending for remapping
        // This allows us to distinguish mouse button presses from keyboard presses
        deviceManager.onInputValue = { [weak self] value in
            self?.processHIDValue(value)
        }
    }

    /// Process HID value from Razer mouse to mark keys as pending for remapping
    private func processHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        // Debug: log all keyboard page events
        if usagePage == 0x07 {
            debugLog("HID Keyboard: usage=0x\(String(usage, radix: 16)) value=\(intValue)")
        }

        // Only process keyboard usage page (0x07) key-down events
        guard usagePage == 0x07, intValue != 0 else { return }

        // Mark this key as pending for remapping
        keyboardEventTap.markKeyPending(hidUsage: UInt32(usage))
    }

    private func debugLog(_ message: String) {
        let logFile = "/tmp/razer-remapper.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
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

    func checkInputMonitoringPermission() {
        hasInputMonitoringPermission = PermissionManager.checkInputMonitoring()
    }

    func requestInputMonitoringPermission() {
        PermissionManager.openInputMonitoringSettings()

        // Check again after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.checkInputMonitoringPermission()
        }
    }

    private func updateRemappingState() {
        if isEnabled {
            // Start the event tap if not already started
            if keyboardEventTap.start() {
                keyboardEventTap.isEnabled = true
                NSLog("[AppState] Remapping enabled")
            }
        } else {
            keyboardEventTap.isEnabled = false
            NSLog("[AppState] Remapping disabled")
        }
    }

    private func startMonitoring() {
        NSLog("[AppState] startMonitoring called, permission: \(hasInputMonitoringPermission)")

        // Try to start monitoring even without confirmed permission
        // The HIDManager will fail to open if permission is not granted
        if !deviceManager.isRunning {
            deviceManager.start()

            // Update initial device state
            isDeviceConnected = deviceManager.connectedDeviceName != nil
            connectedDeviceName = deviceManager.connectedDeviceName
            NSLog("[AppState] Device connected: \(isDeviceConnected), name: \(connectedDeviceName ?? "none")")
        }
    }
}

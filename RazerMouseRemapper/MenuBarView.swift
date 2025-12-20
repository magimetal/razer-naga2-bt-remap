import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Razer Remapper")
                    .font(.headline)
            }
            .padding(.bottom, 4)

            Divider()

            // Permission warning - only show if no device detected (implies no permission)
            if !appState.isDeviceConnected && !appState.hasInputMonitoringPermission {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Input Monitoring permission required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Grant Permission") {
                    appState.requestInputMonitoringPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Divider()
            }

            // Device status
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.isDeviceConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                if let deviceName = appState.connectedDeviceName {
                    Text(deviceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No Razer device connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Main toggle
            Toggle(isOn: $appState.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Remapping")
                        .font(.body)
                    Text("Side buttons 1-9,0,-,= → F1-F12")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(!appState.isDeviceConnected)

            Divider()

            // Launch at login
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLoginManager.setEnabled(newValue)
                }

            Divider()

            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Quit button
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            launchAtLogin = LaunchAtLoginManager.isEnabled
            appState.checkInputMonitoringPermission()
        }
    }

    private var statusColor: Color {
        if !appState.isDeviceConnected {
            return .orange
        } else if appState.isEnabled {
            return .green
        } else {
            return .gray
        }
    }

    private var statusText: String {
        if !appState.isDeviceConnected {
            return "Waiting for Razer device..."
        } else if appState.isEnabled {
            return "Active - remapping keys"
        } else {
            return "Disabled"
        }
    }
}

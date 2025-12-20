# Razer Mouse Remapper

A macOS menu bar app that remaps Razer Naga side buttons (1-9, 0, -, =) to F1-F12 keys.

## Features

- **Selective Remapping**: Only remaps keys from the Razer mouse - your keyboard numbers work normally
- **Menu Bar Control**: Toggle remapping on/off from the menu bar
- **Auto-Start**: Launches automatically on login via Launch Agent
- **Low Overhead**: Uses native macOS HID and CGEvent APIs

## Supported Devices

- Razer Naga V2 HS (Bluetooth: VID 0x68E, PID 0xB5)
- Other Razer devices with VID 0x1532 (USB)

## Requirements

- macOS 14.0+
- Swift 5.9+

## Permissions Required

The app requires two permissions in **System Settings → Privacy & Security**:

1. **Input Monitoring** - To receive HID events from the mouse
2. **Accessibility** - To intercept and remap keyboard events

## Installation

### Build

```bash
./build-app.sh
```

### Grant Permissions

1. Open **System Settings → Privacy & Security → Input Monitoring**
   - Add `RazerMouseRemapper.app`
   - Enable the checkbox

2. Open **System Settings → Privacy & Security → Accessibility**
   - Add `RazerMouseRemapper.app`
   - Enable the checkbox

### Enable Auto-Start

The Launch Agent is installed at:
```
~/Library/LaunchAgents/com.razer.mouseremapper.plist
```

To load/enable:
```bash
launchctl load ~/Library/LaunchAgents/com.razer.mouseremapper.plist
```

To start manually:
```bash
launchctl start com.razer.mouseremapper
```

## Usage

Once running, a gamecontroller icon appears in the menu bar:

- **Filled icon**: Remapping is enabled
- **Outline icon**: Remapping is disabled

Click the icon to toggle remapping or access settings.

## Key Mapping

| Mouse Button | Sends | Remapped To |
|--------------|-------|-------------|
| 1            | 1     | F1          |
| 2            | 2     | F2          |
| 3            | 3     | F3          |
| 4            | 4     | F4          |
| 5            | 5     | F5          |
| 6            | 6     | F6          |
| 7            | 7     | F7          |
| 8            | 8     | F8          |
| 9            | 9     | F9          |
| 10           | 0     | F10         |
| 11           | -     | F11         |
| 12           | =     | F12         |

## How It Works

1. **HID Monitoring**: Detects when a key event originates from the Razer mouse via IOHIDManager
2. **Event Correlation**: Marks the key as "pending" when detected from mouse HID
3. **CGEvent Tap**: Intercepts the system keyboard event
4. **Selective Remap**: Only remaps if the key was recently detected from the mouse (within 50ms)

This ensures keyboard number keys work normally while mouse buttons get remapped.

## Managing the Launch Agent

```bash
# Stop the app
launchctl stop com.razer.mouseremapper

# Start the app
launchctl start com.razer.mouseremapper

# Disable auto-start
launchctl unload ~/Library/LaunchAgents/com.razer.mouseremapper.plist

# Re-enable auto-start
launchctl load ~/Library/LaunchAgents/com.razer.mouseremapper.plist

# Check if running
ps aux | grep RazerMouseRemapper
```

## Troubleshooting

### App doesn't detect mouse
- Ensure Input Monitoring permission is granted
- Check if device appears: the app logs to `/tmp/razer-remapper.log`

### Keys not remapped
- Ensure Accessibility permission is granted
- Check menu bar icon shows filled (enabled)
- View logs: `cat /tmp/razer-remapper.log | grep REMAPPED`

### App doesn't start on login
- Verify Launch Agent is loaded: `launchctl list | grep razer`
- Check logs: `cat /tmp/razer-remapper-stderr.log`

## Debug Logs

- **App log**: `/tmp/razer-remapper.log`
- **Stdout**: `/tmp/razer-remapper-stdout.log`
- **Stderr**: `/tmp/razer-remapper-stderr.log`

## Diagnostic Tool

A standalone diagnostic script is included to test mouse input:

```bash
swift diagnose-mouse.swift
```

This shows raw HID events and CGEvents from the mouse.

## Project Structure

```
├── RazerMouseRemapper/
│   ├── RazerMouseRemapperApp.swift  # Main app and state management
│   ├── RazerDeviceManager.swift     # HID device detection and monitoring
│   ├── KeyboardEventTap.swift       # CGEvent interception and remapping
│   ├── KeyRemapper.swift            # HID-based key processing
│   ├── SyntheticKeyEmitter.swift    # Synthetic key event generation
│   ├── MenuBarView.swift            # Menu bar UI
│   ├── PermissionManager.swift      # Permission checking
│   └── LaunchAtLoginManager.swift   # Login item management
├── diagnose-mouse.swift             # Standalone diagnostic tool
├── build-app.sh                     # Build script
└── Package.swift                    # Swift package manifest
```

## License

MIT

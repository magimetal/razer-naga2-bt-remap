// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RazerMouseRemapper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RazerMouseRemapper", targets: ["RazerMouseRemapper"])
    ],
    targets: [
        .executableTarget(
            name: "RazerMouseRemapper",
            path: "RazerMouseRemapper",
            sources: [
                "RazerMouseRemapperApp.swift",
                "MenuBarView.swift",
                "RazerDeviceManager.swift",
                "KeyRemapper.swift",
                "KeyboardEventTap.swift",
                "SyntheticKeyEmitter.swift",
                "LaunchAtLoginManager.swift",
                "PermissionManager.swift"
            ]
        )
    ]
)

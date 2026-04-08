// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SteamGuardMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SteamGuardMac",
            path: "Sources/SteamGuardMac"
        )
    ]
)

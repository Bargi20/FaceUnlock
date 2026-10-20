// swift-tools-version: 5.10
// NotchUnlock: Face ID-style unlock for the Mac, from a square that drops out
// of the notch. Engine ported from FaceMac (GPL-3.0).
import PackageDescription

let package = Package(
    name: "NotchUnlock",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Shows the notch window above the lock screen.
        .package(url: "https://github.com/Lakr233/SkyLightWindow", exact: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotchUnlock",
            dependencies: [.product(name: "SkyLightWindow", package: "SkyLightWindow")],
            path: "Sources/NotchUnlock"
        ),
    ]
)

// swift-tools-version:5.9
// WidgetForgeKit: the platform-independent core of WidgetForge (models, engines, security).
// The macOS app and WidgetKit extension are built from WidgetForge.xcodeproj; this package exists so the
// core can be unit-tested with `swift test` without launching the app.
import PackageDescription

let package = Package(
    name: "WidgetForge",
    platforms: [.macOS(.v14)],
    products: [.library(name: "WidgetForgeKit", targets: ["WidgetForgeKit"])],
    targets: [
        .target(
            name: "WidgetForgeKit",
            path: "Sources",
            exclude: ["App", "Desktop", "UI", "Builder", "Widgets"]
        ),
        .testTarget(
            name: "WidgetForgeKitTests",
            dependencies: ["WidgetForgeKit"],
            path: "Tests"
        ),
    ]
)

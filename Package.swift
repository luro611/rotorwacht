// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Rotorwacht",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Rotorwacht", targets: ["Rotorwacht"]),
    ],
    targets: [
        // Pure game logic: physics, rules, mission data. No UI, fully testable.
        .target(
            name: "RotorwachtCore",
            resources: [.copy("Missions")]
        ),
        // The Mac app: SpriteKit scene, SwiftUI menus, audio.
        .executableTarget(
            name: "Rotorwacht",
            dependencies: ["RotorwachtCore"],
            resources: [.copy("Fonts"), .copy("Images")]
        ),
        .testTarget(
            name: "RotorwachtCoreTests",
            dependencies: ["RotorwachtCore"]
        ),
    ]
)

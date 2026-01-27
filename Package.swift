// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spook",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Spook", targets: ["Spook"])
    ],
    targets: [
        .executableTarget(
            name: "Spook",
            path: "Sources/Spook",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)

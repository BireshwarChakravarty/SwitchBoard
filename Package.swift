// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [
        .macOS("26.0") // Liquid Glass (glassEffect, glass button styles)
    ],
    targets: [
        .executableTarget(
            name: "Switchboard",
            path: "Sources/Switchboard",
            linkerSettings: [
                // IOAVService* (Apple Silicon DDC) lives in IOKit but is not in the public headers.
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DittoBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DittoBar", targets: ["DittoBar"])
    ],
    targets: [
        .executableTarget(
            name: "DittoBar",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)

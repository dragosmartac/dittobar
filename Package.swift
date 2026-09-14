// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BarCheatSheets",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BarCheatSheets", targets: ["BarCheatSheets"])
    ],
    targets: [
        .executableTarget(
            name: "BarCheatSheets",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)

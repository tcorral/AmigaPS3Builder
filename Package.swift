// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AmigaPS3Builder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "AmigaPS3Builder",
            targets: ["AmigaPS3Builder"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AmigaPS3Builder",
            path: "Sources/AmigaPS3Builder"
        )
    ]
)

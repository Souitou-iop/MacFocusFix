// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MacFocusFix",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacFocusFix", targets: ["MacFocusFix"])
    ],
    targets: [
        .executableTarget(
            name: "MacFocusFix",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)

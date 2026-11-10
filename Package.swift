// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipVault",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClipVault", targets: ["ClipVault"])
    ],
    dependencies: [
        .package(url: "https://github.com/georgecristea/MacUtilityKit.git", from: "0.1.0")
    ],
    targets: [
        .executableTarget(
            name: "ClipVault",
            dependencies: [
                "MacUtilityKit"
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "ClipVaultTests",
            dependencies: ["ClipVault"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)

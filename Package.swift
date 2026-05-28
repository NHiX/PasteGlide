// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasteGlide",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "PasteGlideCore",
            linkerSettings: [
                .linkedFramework("Vision"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "PasteGlide",
            dependencies: ["PasteGlideCore"]
        ),
        .executableTarget(
            name: "PasteGlideCoreTests",
            dependencies: ["PasteGlideCore"]
        )
    ]
)

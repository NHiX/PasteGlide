// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasteGlide",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "PasteGlideShared"
        ),
        .target(
            name: "PasteGlideCore",
            dependencies: ["PasteGlideShared"],
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
            name: "PasteGlidePortable",
            dependencies: ["PasteGlideShared"]
        ),
        .executableTarget(
            name: "PasteGlideSharedTests",
            dependencies: ["PasteGlideShared"]
        ),
        .executableTarget(
            name: "PasteGlideCoreTests",
            dependencies: ["PasteGlideCore", "PasteGlideShared"]
        )
    ]
)

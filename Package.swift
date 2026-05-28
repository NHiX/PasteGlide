// swift-tools-version: 6.0
import PackageDescription

var platforms: [SupportedPlatform] = []
var targets: [Target] = [
    .target(
        name: "PasteGlideShared"
    ),
    .executableTarget(
        name: "PasteGlidePortable",
        dependencies: ["PasteGlideShared"]
    ),
    .executableTarget(
        name: "PasteGlideSharedTests",
        dependencies: ["PasteGlideShared"]
    )
]

#if os(macOS)
platforms = [
    .macOS(.v14)
]

targets.insert(
    contentsOf: [
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
            name: "PasteGlideCoreTests",
            dependencies: ["PasteGlideCore", "PasteGlideShared"]
        )
    ],
    at: 1
)
#endif

let package = Package(
    name: "PasteGlide",
    platforms: platforms,
    targets: targets
)

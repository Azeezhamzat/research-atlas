// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ResearchAtlas",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ResearchAtlas", targets: ["ResearchAtlasApp"]),
        .executable(name: "ResearchAtlasChecks", targets: ["ResearchAtlasChecks"]),
        .executable(name: "ResearchAtlasPerformance", targets: ["ResearchAtlasPerformance"])
    ],
    targets: [
        .target(
            name: "ResearchAtlasCore",
            path: "AppSources/ResearchAtlasCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "ResearchAtlasApp",
            dependencies: ["ResearchAtlasCore"],
            path: "AppSources/ResearchAtlasApp",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "ResearchAtlasChecks",
            dependencies: ["ResearchAtlasCore"],
            path: "AppSources/ResearchAtlasChecks"
        ),
        .executableTarget(
            name: "ResearchAtlasPerformance",
            dependencies: ["ResearchAtlasCore"],
            path: "AppSources/ResearchAtlasPerformance"
        )
    ]
)

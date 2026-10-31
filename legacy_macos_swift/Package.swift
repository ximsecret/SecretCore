// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalVault",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LocalVault", targets: ["LocalVault"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LocalVault",
            dependencies: [],
            path: "Sources/LocalVault"
        )
    ]
)

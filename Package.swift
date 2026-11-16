// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppVault",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AppVault", targets: ["AppVault"])],
    targets: [
        .executableTarget(name: "AppVault"),
        .testTarget(name: "AppVaultTests", dependencies: ["AppVault"])
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapStack",
    platforms: [.macOS("13.5")],
    products: [.executable(name: "SnapStack", targets: ["SnapStack"])],
    targets: [.executableTarget(name: "SnapStack")]
)

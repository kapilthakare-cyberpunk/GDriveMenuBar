// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GDriveMenuBar",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GDriveMenuBar", targets: ["GDriveMenuBar"])],
    targets: [.executableTarget(name: "GDriveMenuBar")]
)

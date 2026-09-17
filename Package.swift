// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VisaGames",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "VisaGames", targets: ["VisaGames"])],
    targets: [
        .target(name: "VisaCore"),
        .executableTarget(name: "VisaGames", dependencies: ["VisaCore"]),
        .executableTarget(name: "VisaCoreChecks", dependencies: ["VisaCore"], path: "Tests/VisaCoreTests")
    ]
)

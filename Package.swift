// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VisaGames",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "VisaGames", targets: ["VisaGames"])],
    targets: [
        .target(name: "VisaCore"),
        .executableTarget(
            name: "VisaGames",
            dependencies: ["VisaCore"],
            swiftSettings: [
                // ADR 0010: keep Swift 6 static isolation checking, but do not emit the SE-0423
                // runtime executor checks (crashed inside the runtime in ShellView.body on main).
                // Unsafe flags are fine here: VisaGames is the root package, never a dependency.
                .unsafeFlags(["-Xfrontend", "-disable-dynamic-actor-isolation"])
            ]
        ),
        .executableTarget(name: "VisaCoreChecks", dependencies: ["VisaCore"], path: "Tests/VisaCoreTests")
    ]
)

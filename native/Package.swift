// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Daaaay",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Daaaay", targets: ["Daaaay"])],
    targets: [
        .target(name: "DayCore"),
        .executableTarget(name: "Daaaay", dependencies: ["DayCore"]),
        .executableTarget(name: "DayCoreChecks", dependencies: ["DayCore"], path: "Tests/DayCoreTests")
    ]
)

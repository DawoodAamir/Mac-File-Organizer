// swift-tools-version: 5.7
import PackageDescription
let package = Package(name: "OrganizerCore", platforms: [.iOS(.v15), .macOS(.v12)], products: [.library(name: "OrganizerCore", targets: ["OrganizerCore"])], targets: [.target(name: "OrganizerCore", path: "Sources/Core"), .testTarget(name: "OrganizerCoreTests", dependencies: ["OrganizerCore"], path: "Tests/Core")])

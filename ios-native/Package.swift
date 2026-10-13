// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HongguoCore", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "HongguoCore", targets: ["HongguoCore"])], targets: [.target(name: "HongguoCore", resources: [.process("Resources")]), .testTarget(name: "HongguoCoreTests", dependencies: ["HongguoCore"], resources: [.process("Fixtures")])])

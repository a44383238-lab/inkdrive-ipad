// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "InkDriveCore", platforms: [.iOS(.v17)], products: [
    .library(name: "InkDriveCore", targets: ["InkDriveCore"])
], targets: [
    .target(name: "InkDriveCore", path: ".", sources: ["Core", "UI"], resources: [.process("Resources/Icons")]),
    .testTarget(name: "InkDriveCoreTests", dependencies: ["InkDriveCore"], path: "Tests"),
    .testTarget(name: "InkDriveEditorTests", dependencies: ["InkDriveCore"], path: "EditorTests", resources: [.copy("Fixtures")])
])

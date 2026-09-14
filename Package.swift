// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CodexMeter", platforms: [.macOS(.v14)],
    products: [.executable(name: "update-probe", targets: ["UpdateProbe"]), .executable(name: "codex-meter", targets: ["CodexMeter"]), .executable(name: "meter-checks", targets: ["MeterChecks"])],
    targets: [
        .binaryTarget(name: "Sparkle", path: ".vendor/Sparkle.xcframework"),
        .systemLibrary(name: "CSQLite"),
        .target(name: "MeterCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "CodexMeter", dependencies: ["MeterCore", "Sparkle"], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "UpdateProbe", dependencies: ["MeterCore", "Sparkle"], path: "Tests/UpdateProbe", linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "MeterChecks", dependencies: ["MeterCore"], path: "Tests/MeterCoreTests")
    ], swiftLanguageModes: [.v5]
)

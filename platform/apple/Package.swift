// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CaeloAppleDiagnostics",
    platforms: [.macOS(.v10_15)],
    targets: [
        .target(name: "CaeloAppleDiagnostics", path: ".",
            exclude: ["Tests", "PacketTunnelProvider.swift", "VpnManager.swift", "Updater.swift", "README.md", "CaeloTunnel-Bridging-Header.h"],
            sources: ["TunnelLog.swift"]),
        .testTarget(name: "DiagnosticsTests", dependencies: ["CaeloAppleDiagnostics"], path: "Tests"),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "colay",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "colay", targets: ["colay"])
    ],
    targets: [
        .executableTarget(
            name: "colay",
            path: "Sources/colay",
            resources: [.copy("Resources")]
        )
    ]
)

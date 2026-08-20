// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkDownNotes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MarkDownNotes", path: "Sources/MarkDownNotes")
    ]
)

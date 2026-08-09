// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "batch-ocr",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "batch-ocr", targets: ["BatchOCR"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "BatchOCR",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/BatchOCR"
        ),
        .testTarget(
            name: "BatchOCRTests",
            dependencies: ["BatchOCR"],
            path: "Tests/BatchOCRTests"
        )
    ]
)

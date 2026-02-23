// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "a2a-swift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "A2A",
            targets: ["A2A"]
        ),
        .executable(
            name: "A2AExample",
            targets: ["A2AExample"]
        ),
    ],
    dependencies: [
        // Protocol Buffer support
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0"),
        
        // HTTP server framework
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        
        // HTTP client
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.30.0"),
        
        // Server-Sent Events support
        .package(url: "https://github.com/orlandos-nl/SSEKit.git", from: "1.1.0"),
        
        // JSON-RPC 2.0 support
        .package(url: "https://github.com/ChimeHQ/JSONRPC.git", from: "0.4.0"),
        
        // AnyCodable for type-erased Codable support
        .package(url: "https://github.com/Flight-School/AnyCodable.git", from: "0.6.0"),

        // Configuration
        .package(url: "https://github.com/apple/swift-configuration", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "A2A",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "SSEKit", package: "SSEKit"),
                .product(name: "JSONRPC", package: "JSONRPC"),
                .product(name: "AnyCodable", package: "AnyCodable"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "A2ATests",
            dependencies: [
                "A2A",
            ]
        ),
        .executableTarget(
            name: "A2AExample",
            dependencies: [
                "A2A",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        ),
    ]
)


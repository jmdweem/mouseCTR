// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "MouseAutoScroll",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "MouseAutoScroll", targets: ["MouseAutoScroll"])
  ],
  targets: [
    .executableTarget(
      name: "MouseAutoScroll",
      path: "Sources/MouseAutoScroll"
    )
  ]
)

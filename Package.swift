// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "SnapshotAlphaRepro",
  platforms: [.iOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution", exact: "7.0.0")
  ],
  targets: [
    .testTarget(
      name: "SnapshotAlphaTests",
      dependencies: [.product(name: "MapLibre", package: "maplibre-gl-native-distribution")]
    )
  ]
)

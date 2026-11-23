import MapLibre
import XCTest

/// One GeoJSON polygon, larger than the view, filled with rgba(255,0,0,0.5) and nothing else.
/// Every pixel of the snapshot should have alpha 128 (one layer of 50 %).
final class SnapshotAlphaTests: XCTestCase {
  // (center longitude, center latitude, span in degrees of latitude)
  let cases: [(Double, Double, Double)] = [
    (2.3522, 48.8566, 0.002),
    (2.3522, 48.8566, 0.008),
    (2.3522, 48.8566, 0.25),
    (2.3001, 48.8901, 0.008),
    (2.3001, 48.8901, 0.03),
  ]

  func testTranslucentFillIsDrawnOnce() throws {
    var failures: [String] = []
    for (lon, lat, span) in cases {
      let alphas = try snapshotAlphas(lon: lon, lat: lat, span: span)
      let summary = alphas.sorted { $0.value > $1.value }.prefix(3)
        .map { "alpha \($0.key): \($0.value * 100 / alphas.values.reduce(0, +)) %" }
        .joined(separator: ", ")
      print("center (\(lon), \(lat)) span \(span)° -> \(summary)")
      if alphas.keys.contains(where: { abs(Int($0) - 128) > 2 }) {
        failures.append("span \(span) at (\(lon), \(lat)): \(summary)")
      }
    }
    XCTAssert(failures.isEmpty, "Fill drawn more than once:\n" + failures.joined(separator: "\n"))
  }

  /// How many pixels have each alpha value.
  func snapshotAlphas(lon: Double, lat: Double, span: Double) throws -> [UInt8: Int] {
    let k = cos(lat * .pi / 180)
    let (w, s, e, n) = (lon - span / 2 / k, lat - span / 2, lon + span / 2 / k, lat + span / 2)
    let g = span * 0.3
    let style: [String: Any] = [
      "version": 8,
      "sources": [
        "p": [
          "type": "geojson",
          "data": [
            "type": "Polygon",
            "coordinates": [[[w - g, s - g], [e + g, s - g], [e + g, n + g], [w - g, n + g], [w - g, s - g]]],
          ],
        ]
      ],
      "layers": [
        ["id": "fill", "type": "fill", "source": "p", "paint": ["fill-color": "rgba(255,0,0,0.5)"]]
      ],
    ]
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("style-\(UUID()).json")
    try JSONSerialization.data(withJSONObject: style).write(to: url)

    let options = MLNMapSnapshotOptions(
      styleURL: url, camera: MLNMapCamera(), size: CGSize(width: 180, height: 180))
    options.coordinateBounds = MLNCoordinateBounds(
      sw: CLLocationCoordinate2D(latitude: s, longitude: w),
      ne: CLLocationCoordinate2D(latitude: n, longitude: e))
    options.showsLogo = false

    let done = expectation(description: "snapshot")
    var image: UIImage?
    let snapshotter = MLNMapSnapshotter(options: options)
    snapshotter.start { snapshot, error in
      XCTAssertNil(error)
      image = snapshot?.image
      done.fulfill()
    }
    wait(for: [done], timeout: 30)
    let cg = try XCTUnwrap(image?.cgImage)

    // Redrawn into a known RGBA8 buffer, premultiplied, so that alpha reads directly.
    let (width, height) = (cg.width, cg.height)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    var counts: [UInt8: Int] = [:]
    for i in stride(from: 3, to: pixels.count, by: 4) { counts[pixels[i], default: 0] += 1 }
    return counts
  }
}

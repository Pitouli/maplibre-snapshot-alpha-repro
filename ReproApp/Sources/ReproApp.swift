import MapLibre
import SwiftUI

/// Snapshots of one GeoJSON polygon, larger than the view, filled with rgba(255,0,0,0.5) and
/// nothing else. Every pixel should have alpha 128 (one layer of 50 %).
@main
struct ReproApp: App {
  var body: some Scene { WindowGroup { ContentView() } }
}

struct Result: Identifiable {
  let id = UUID()
  let label: String
  let summary: String
  let ok: Bool
  let image: UIImage
}

struct ContentView: View {
  @State private var results: [Result] = []
  @State private var status = "Starting…"

  var body: some View {
    VStack(alignment: .leading) {
      Text(status).font(.footnote.monospaced()).padding(.horizontal)
      list
    }
    .task { await run() }
  }

  var list: some View {
    List(results) { r in
      HStack {
        Image(uiImage: r.image).resizable().frame(width: 72, height: 72)
          .background(Color.white)
        VStack(alignment: .leading) {
          Text(r.label).font(.headline)
          Text(r.summary).font(.caption.monospaced())
          Text(r.ok ? "OK: drawn once" : "WRONG: drawn more than once")
            .foregroundStyle(r.ok ? .green : .red)
        }
      }
    }
  }

  @MainActor func run() async {
    // The five cases first, then a sweep: 39 centers around the world × spans from 0.001° to 2°
    // (deterministic, so that a run can be repeated).
    var cases: [(Double, Double, Double)] = [
      (2.3522, 48.8566, 0.002),
      (2.3522, 48.8566, 0.008),
      (2.3522, 48.8566, 0.25),
      (2.3001, 48.8901, 0.008),
      (2.3001, 48.8901, 0.03),
    ]
    var seed: UInt64 = 42
    func next() -> Double {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return Double(seed >> 11) / Double(1 << 53)
    }
    for _ in 0..<195 {
      let lat = -60 + next() * 130
      let lon = -180 + next() * 360
      let span = 0.001 * pow(2000, next())
      cases.append(((lon * 1e4).rounded() / 1e4, (lat * 1e4).rounded() / 1e4, (span * 1e5).rounded() / 1e5))
    }
    for (index, (lon, lat, span)) in cases.enumerated() {
      status = "Rendering \(index + 1)/\(cases.count)…"
      let (image, error) = await snapshot(lon: lon, lat: lat, span: span)
      guard let image else {
        status = "Case \(index + 1) failed: \(error ?? "no image")"
        print(status)
        return
      }
      let counts = alphaCounts(image)
      let total = counts.values.reduce(0, +)
      let summary = counts.sorted { $0.value > $1.value }.prefix(2)
        .map { "alpha \($0.key): \($0.value * 100 / total) %" }.joined(separator: ", ")
      let ok = !counts.keys.contains { abs(Int($0) - 128) > 2 }
      let label = "(\(lon), \(lat)) span \(span)°"
      print("\(label) -> \(summary)")
      results.append(Result(label: label, summary: summary, ok: ok, image: image))
    }
    results.sort { !$0.ok && $1.ok }
    status = "Done: \(results.filter(\.ok).count)/\(results.count) OK"
    print(status)
  }
}

@MainActor func snapshot(lon: Double, lat: Double, span: Double) async -> (UIImage?, String?) {
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
  guard let data = try? JSONSerialization.data(withJSONObject: style), (try? data.write(to: url)) != nil
  else { return (nil, "could not write the style") }
  let options = MLNMapSnapshotOptions(
    styleURL: url, camera: MLNMapCamera(), size: CGSize(width: 180, height: 180))
  options.coordinateBounds = MLNCoordinateBounds(
    sw: CLLocationCoordinate2D(latitude: s, longitude: w),
    ne: CLLocationCoordinate2D(latitude: n, longitude: e))
  options.showsLogo = false
  let snapshotter = MLNMapSnapshotter(options: options)
  return await withCheckedContinuation { continuation in
    snapshotter.start { snapshot, error in
      _ = snapshotter
      continuation.resume(returning: (snapshot?.image, error.map { "\($0)" }))
    }
  }
}

/// How many pixels have each alpha value, read from a known premultiplied RGBA8 buffer.
func alphaCounts(_ image: UIImage) -> [UInt8: Int] {
  guard let cg = image.cgImage else { return [:] }
  let (width, height) = (cg.width, cg.height)
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  guard
    let context = CGContext(
      data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return [:] }
  context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
  var counts: [UInt8: Int] = [:]
  for i in stride(from: 3, to: pixels.count, by: 4) { counts[pixels[i], default: 0] += 1 }
  return counts
}

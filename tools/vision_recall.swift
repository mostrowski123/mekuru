// Measures how well Apple's Vision text detection finds the text blocks of a
// manga volume, against a reference .mokuro file (IOS-42: Vision replaces the
// GPL comic-text-detector on iOS). Runs on macOS; Vision is the same framework.
//
//   swift tools/vision_recall.swift example/mokuro/test1.mokuro \
//       [--legacy] [--min-text-height 0.005] [--tile 2x3] [--rotate] [--json out.json]
//
// Measures the Swift Vision API: RecognizeTextRequest (iOS 18+, line boxes) and
// RecognizeDocumentsRequest (iOS 26+, paragraph boxes). --legacy measures the
// older VNRecognizeTextRequest / VNDetectTextRectanglesRequest instead, which
// barely see vertical text (kept so that result can be reproduced).
//
// --min-text-height: Vision ignores text shorter than this fraction of the
//   image height (default here 0 = no limit; Vision's own default is 1/32).
//   --tile COLSxROWS runs Vision on overlapping tiles of the page instead of
//   the whole page. --rotate turns the page a quarter turn first, so vertical
//   columns reach Vision as horizontal lines (boxes are mapped back).
//
// Images are read from the folder next to the .mokuro file with the same name.
// A reference block counts as found when Vision's boxes cover at least half of
// its area. The text score compares Vision's own reading with the reference,
// which is itself manga-ocr output, not ground truth: informational only.

import CoreGraphics
import Foundation
import ImageIO
import Vision

struct Box {
  var x0: Double, y0: Double, x1: Double, y1: Double
  var area: Double { max(0, x1 - x0) * max(0, y1 - y0) }
  func intersection(_ o: Box) -> Double {
    Box(x0: max(x0, o.x0), y0: max(y0, o.y0), x1: min(x1, o.x1), y1: min(y1, o.y1)).area
  }
}

struct Found { let box: Box; let text: String }

/// Vision reports normalised rects with a bottom-left origin.
func pixelBox(_ r: CGRect, _ w: Double, _ h: Double) -> Box {
  Box(x0: r.minX * w, y0: (1 - r.maxY) * h, x1: r.maxX * w, y1: (1 - r.minY) * h)
}

func loadImage(_ url: URL) -> CGImage? {
  guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func option(_ name: String) -> String? {
  let args = CommandLine.arguments
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
  return args[i + 1]
}

let minTextHeight = option("--min-text-height").flatMap(Float.init) ?? 0
let legacy = CommandLine.arguments.contains("--legacy")
let tileGrid: (cols: Int, rows: Int) = {
  let parts = (option("--tile") ?? "1x1").split(separator: "x").compactMap { Int($0) }
  return parts.count == 2 ? (parts[0], parts[1]) : (1, 1)
}()

/// The page cut into a grid of tiles that overlap by 15% of a tile, so text
/// on a seam is whole in at least one of them.
func tiles(of image: CGImage) -> [(image: CGImage, dx: Double, dy: Double)] {
  let (cols, rows) = tileGrid
  if cols == 1 && rows == 1 { return [(image, 0, 0)] }
  let (w, h) = (Double(image.width), Double(image.height))
  let (tw, th) = (w / Double(cols), h / Double(rows))
  var out: [(CGImage, Double, Double)] = []
  for r in 0..<rows {
    for c in 0..<cols {
      let x0 = max(0, Double(c) * tw - 0.15 * tw), y0 = max(0, Double(r) * th - 0.15 * th)
      let x1 = min(w, Double(c + 1) * tw + 0.15 * tw), y1 = min(h, Double(r + 1) * th + 0.15 * th)
      let rect = CGRect(x: x0.rounded(), y: y0.rounded(), width: (x1 - x0).rounded(), height: (y1 - y0).rounded())
      if let tile = image.cropping(to: rect) { out.append((tile, Double(rect.minX), Double(rect.minY))) }
    }
  }
  return out
}

let rotate = CommandLine.arguments.contains("--rotate")

/// The page turned 90 degrees counter-clockwise.
func rotatedCCW(_ image: CGImage) -> CGImage {
  let (w, h) = (image.width, image.height)
  let ctx = CGContext(
    data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.translateBy(x: CGFloat(h), y: 0)
  ctx.rotate(by: .pi / 2)
  ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
  return ctx.makeImage()!
}

/// A box found on the rotated page, back in the original page's pixels.
func unrotated(_ f: Found, pageWidth w: Double) -> Found {
  Found(box: Box(x0: w - f.box.y1, y0: f.box.x0, x1: w - f.box.y0, y1: f.box.x1), text: f.text)
}

func recognizeText(_ page: CGImage) throws -> [Found] {
  try tiles(of: page).flatMap { tile -> [Found] in
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP"]
    request.usesLanguageCorrection = true
    request.minimumTextHeight = minTextHeight
    try VNImageRequestHandler(cgImage: tile.image, options: [:]).perform([request])
    let (w, h) = (Double(tile.image.width), Double(tile.image.height))
    return (request.results ?? []).map {
      var box = pixelBox($0.boundingBox, w, h)
      box.x0 += tile.dx; box.x1 += tile.dx; box.y0 += tile.dy; box.y1 += tile.dy
      return Found(box: box, text: $0.topCandidates(1).first?.string ?? "")
    }
  }
}

func detectRectangles(_ page: CGImage) throws -> [Found] {
  try tiles(of: page).flatMap { tile -> [Found] in
    let request = VNDetectTextRectanglesRequest()
    request.reportCharacterBoxes = false
    try VNImageRequestHandler(cgImage: tile.image, options: [:]).perform([request])
    let (w, h) = (Double(tile.image.width), Double(tile.image.height))
    return (request.results ?? []).map {
      var box = pixelBox($0.boundingBox, w, h)
      box.x0 += tile.dx; box.x1 += tile.dx; box.y0 += tile.dy; box.y1 += tile.dy
      return Found(box: box, text: "")
    }
  }
}

/// Line-level boxes from the Swift Vision API (iOS 18+).
func recognizeTextModern(_ page: CGImage) async throws -> [Found] {
  var out: [Found] = []
  for tile in tiles(of: page) {
    var request = RecognizeTextRequest()
    request.recognitionLanguages = [Locale.Language(identifier: "ja-JP")]
    request.recognitionLevel = .accurate
    request.minimumTextHeightFraction = minTextHeight
    let (w, h) = (Double(tile.image.width), Double(tile.image.height))
    for line in try await request.perform(on: tile.image) {
      var box = pixelBox(line.boundingBox.cgRect, w, h)
      box.x0 += tile.dx; box.x1 += tile.dx; box.y0 += tile.dy; box.y1 += tile.dy
      out.append(Found(box: box, text: line.topCandidates(1).first?.string ?? ""))
    }
  }
  return out
}

/// Paragraph-level boxes (Vision's own grouping) from the document request.
@available(macOS 26.0, *)
func recognizeParagraphs(_ page: CGImage) async throws -> [Found] {
  let (w, h) = (Double(page.width), Double(page.height))
  return try await RecognizeDocumentsRequest().perform(on: page).flatMap { doc in
    doc.document.paragraphs.map {
      Found(box: pixelBox($0.boundingRegion.boundingBox.cgRect, w, h), text: $0.transcript)
    }
  }
}

func editDistance(_ a: [Character], _ b: [Character]) -> Int {
  if a.isEmpty { return b.count }
  if b.isEmpty { return a.count }
  var prev = Array(0...b.count)
  for i in 1...a.count {
    var cur = [i] + Array(repeating: 0, count: b.count)
    for j in 1...b.count {
      cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
    }
    prev = cur
  }
  return prev[b.count]
}

/// Folds full-width ASCII to half-width and drops whitespace, so layout
/// differences do not count as reading errors.
func normalise(_ s: String) -> [Character] {
  Array(
    (s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s)
      .filter { !$0.isWhitespace })
}

struct Tally {
  var blocks = 0, found = 0, foundLoose = 0, pieces = 0, stray = 0, boxes = 0
  var verticalBlocks = 0, verticalFound = 0
  var editErrors = 0, refChars = 0
}

func score(_ found: [Found], blocks: [[String: Any]], into t: inout Tally, scoreText: Bool) {
  t.boxes += found.count
  var usedByAnyBlock = Set<Int>()
  for block in blocks {
    guard let b = block["box"] as? [Double] else { continue }
    let ref = Box(x0: b[0], y0: b[1], x1: b[2], y1: b[3])
    let vertical = block["vertical"] as? Bool ?? false
    t.blocks += 1
    if vertical { t.verticalBlocks += 1 }

    // Pieces: Vision boxes lying mostly inside this block.
    let inside = found.enumerated().filter { $0.element.box.intersection(ref) >= 0.5 * $0.element.box.area }
    inside.forEach { usedByAnyBlock.insert($0.offset) }
    let covered = min(1, found.reduce(0) { $0 + $1.box.intersection(ref) } / max(ref.area, 1))
    if covered >= 0.25 { t.foundLoose += 1 }
    guard covered >= 0.5 else { continue }
    t.found += 1
    if vertical { t.verticalFound += 1 }
    t.pieces += inside.count

    if scoreText {
      // Vertical text reads right to left; horizontal top to bottom.
      let ordered = inside.map(\.element).sorted {
        vertical ? $0.box.x0 > $1.box.x0 : $0.box.y0 < $1.box.y0
      }
      let got = normalise(ordered.map(\.text).joined())
      let want = normalise((block["lines"] as? [String] ?? []).joined())
      t.editErrors += editDistance(got, want)
      t.refChars += want.count
    }
  }
  t.stray += found.count - usedByAnyBlock.count
}

func report(_ name: String, _ t: Tally) {
  func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "n/a" : String(format: "%.1f%%", 100 * Double(a) / Double(b)) }
  print("\n\(name)")
  print("  blocks found (>=50% covered): \(t.found)/\(t.blocks)  \(pct(t.found, t.blocks))")
  print("  blocks found (>=25% covered): \(t.foundLoose)/\(t.blocks)  \(pct(t.foundLoose, t.blocks))")
  print("  vertical blocks found:        \(t.verticalFound)/\(t.verticalBlocks)  \(pct(t.verticalFound, t.verticalBlocks))")
  print("  Vision boxes: \(t.boxes), outside every reference block: \(t.stray)")
  if t.found > 0 { print(String(format: "  Vision boxes per found block: %.2f", Double(t.pieces) / Double(t.found))) }
  if t.refChars > 0 { print("  Vision's own text vs reference (CER, informational): \(pct(t.editErrors, t.refChars))") }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
  print("usage: swift tools/vision_recall.swift <volume.mokuro> [--legacy] [--min-text-height F] [--tile CxR] [--rotate] [--json out.json]")
  exit(2)
}
let mokuroURL = URL(fileURLWithPath: args[1])
let imageDir = mokuroURL.deletingPathExtension()
guard
  let data = try? Data(contentsOf: mokuroURL),
  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
  let pages = root["pages"] as? [[String: Any]]
else {
  print("cannot read \(mokuroURL.path)")
  exit(1)
}

var first = Tally(), second = Tally()
var dump: [[String: Any]] = []
let started = Date()
for page in pages {
  guard let name = page["img_path"] as? String, let blocks = page["blocks"] as? [[String: Any]],
    let image = loadImage(imageDir.appendingPathComponent(name))
  else {
    print("skipping page: \(page["img_path"] ?? "?")")
    continue
  }
  let work = rotate ? rotatedCCW(image) : image
  var a: [Found]
  var b: [Found] = []
  if legacy {
    a = try recognizeText(work)
    b = try detectRectangles(work)
  } else {
    a = try await recognizeTextModern(work)
    if #available(macOS 26.0, *) { b = try await recognizeParagraphs(work) }
  }
  if rotate {
    a = a.map { unrotated($0, pageWidth: Double(image.width)) }
    b = b.map { unrotated($0, pageWidth: Double(image.width)) }
  }
  var pageTally = Tally()
  score(a, blocks: blocks, into: &pageTally, scoreText: false)
  print("\(name): \(pageTally.found)/\(pageTally.blocks) blocks, \(a.count) + \(b.count) boxes")
  // Overlapping tiles report seam text twice, and rotated text is unreadable,
  // so the text score only means something on the plain page.
  let scoreText = tileGrid == (1, 1) && !rotate
  score(a, blocks: blocks, into: &first, scoreText: scoreText)
  score(b, blocks: blocks, into: &second, scoreText: scoreText && !legacy)
  dump.append([
    "img_path": name,
    "first": a.map { ["box": [$0.box.x0, $0.box.y0, $0.box.x1, $0.box.y1], "text": $0.text] },
    "second": b.map { ["box": [$0.box.x0, $0.box.y0, $0.box.x1, $0.box.y1], "text": $0.text] },
  ])
}

report(legacy ? "VNRecognizeTextRequest (ja-JP, accurate)" : "RecognizeTextRequest (ja-JP, accurate), line boxes", first)
report(legacy ? "VNDetectTextRectanglesRequest" : "RecognizeDocumentsRequest, paragraph boxes", second)
print(String(format: "\n%.1f s for %d pages, both requests", Date().timeIntervalSince(started), pages.count))
print("settings: legacy \(legacy), min-text-height \(minTextHeight), tile \(tileGrid.cols)x\(tileGrid.rows), rotate \(rotate)")

if let path = option("--json") {
  let out = try JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted])
  try out.write(to: URL(fileURLWithPath: path))
}

// bartool: reads a picture of the menu bar and says how light our item's mark is against the bar. CI only
// (.github/workflows/menu-pictures.yml, through scripts/ci/drive-menu-bar.sh; look step 6, issue 183). It only reads
// PNG files and writes one: it never moves the pointer, presses a key, starts the app or changes a setting.
//
//   bartool read <png> <x> <y> <w> <h>
//       The rectangle in points from the picture's top left, at NSScreen.main's backingScaleFactor pixels per point
//       (1 on the runners), or at BAR_SCALE when that is set. Prints
//       "read bar=<L> far=<L> mean=<L> inkpx=<n> box=<w>x<h>":
//         L       a pixel's relative luminance, WCAG 2.2 (https://www.w3.org/TR/WCAG22/#dfn-relative-luminance), the
//                 formula Sources/MacMoshKit/Look/Contrast.swift writes, from the pixel converted to sRGB (a
//                 screenshot carries the display's profile, not sRGB);
//         bar     the median L of the rectangle's outermost ring of pixels;
//         ink     the pixels whose L is at least 0.1 from bar; inkpx counts them;
//         far     the L of the ink pixel farthest from bar (bar when there is no ink);
//         mean    the mean L of the ink pixels (bar when there is none);
//         box     the ink's bounding box, in points (0x0 when there is none).
//   bartool zoom <png> <x> <y> <w> <h> <out.png>
//       That rectangle, 8 pixels for every pixel, nearest neighbour. Prints "zoom <out.png> <width> <height>".
//
// It exits 1 when the picture cannot be read or written, and 2 on a wrong call. Built by the driver with swiftc, as
// a single file.
import AppKit

func fail(_ message: String, _ code: Int32 = 1) -> Never {
    print(message)
    exit(code)
}

let args = CommandLine.arguments
let usage = "usage: bartool read <png> <x> <y> <w> <h> | bartool zoom <png> <x> <y> <w> <h> <out.png>"
guard args.count >= 7, ["read", "zoom"].contains(args[1]) else { fail(usage, 2) }
guard let x = Double(args[3]), let y = Double(args[4]), let w = Double(args[5]), let h = Double(args[6]),
      w > 0, h > 0 else { fail(usage, 2) }
if args[1] == "read" && args.count != 7 || args[1] == "zoom" && args.count != 8 { fail(usage, 2) }

let scale: Double = {
    if let s = ProcessInfo.processInfo.environment["BAR_SCALE"], let v = Double(s), v > 0 { return v }
    return Double(NSScreen.main?.backingScaleFactor ?? 1)
}()

guard let data = FileManager.default.contents(atPath: args[2]), let rep = NSBitmapImageRep(data: data) else {
    fail("bartool: cannot read \(args[2])")
}
// The rectangle in pixels, clipped to the picture.
let px0 = max(0, Int((x * scale).rounded())), py0 = max(0, Int((y * scale).rounded()))
let px1 = min(rep.pixelsWide, Int(((x + w) * scale).rounded())), py1 = min(rep.pixelsHigh, Int(((y + h) * scale).rounded()))
guard px1 > px0, py1 > py0 else { fail("bartool: the rectangle is outside the picture (\(rep.pixelsWide)x\(rep.pixelsHigh) pixels)") }

func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

/// The pixel's WCAG relative luminance, or nil when it cannot be read.
func luminance(_ px: Int, _ py: Int) -> Double? {
    guard let c = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { return nil }
    return 0.2126 * linear(Double(c.redComponent)) + 0.7152 * linear(Double(c.greenComponent))
        + 0.0722 * linear(Double(c.blueComponent))
}

if args[1] == "zoom" {
    let k = 8
    let width = (px1 - px0) * k, height = (py1 - py0) * k
    // The bytes are written by hand, as sRGB, and the bitmap is tagged sRGB before it is saved.
    guard let made = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: width * 4, bitsPerPixel: 32),
          let bytes = made.bitmapData else { fail("bartool: cannot make a bitmap") }
    for py in py0..<py1 { for px in px0..<px1 {
        let c = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB)
        let rgba = [c?.redComponent ?? 0, c?.greenComponent ?? 0, c?.blueComponent ?? 0, c?.alphaComponent ?? 0]
            .map { UInt8((min(max($0, 0), 1) * 255).rounded()) }
        for dy in 0..<k { for dx in 0..<k {
            let i = (((py - py0) * k + dy) * width + (px - px0) * k + dx) * 4
            for j in 0..<4 { bytes[i + j] = rgba[j] }
        } }
    } }
    let out = made.retagging(with: .sRGB) ?? made
    guard let png = out.representation(using: .png, properties: [:]) else { fail("bartool: cannot make the PNG") }
    do { try png.write(to: URL(fileURLWithPath: args[7])) } catch { fail("bartool: cannot write \(args[7]): \(error)") }
    print("zoom \(args[7]) \(width) \(height)")
    exit(0)
}

var ring: [Double] = []
for py in py0..<py1 { for px in px0..<px1 where px == px0 || px == px1 - 1 || py == py0 || py == py1 - 1 {
    if let l = luminance(px, py) { ring.append(l) } } }
guard !ring.isEmpty else { fail("bartool: no pixel of the rectangle could be read") }
ring.sort()
let bar = ring[ring.count / 2]
var far = bar, sum = 0.0, ink = 0
var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
for py in py0..<py1 { for px in px0..<px1 {
    guard let l = luminance(px, py), abs(l - bar) >= 0.1 else { continue }
    ink += 1
    sum += l
    if abs(l - bar) > abs(far - bar) { far = l }
    minX = min(minX, px); maxX = max(maxX, px); minY = min(minY, py); maxY = max(maxY, py)
} }
let mean = ink > 0 ? sum / Double(ink) : bar
let box = ink > 0 ? String(format: "%gx%g", Double(maxX - minX + 1) / scale, Double(maxY - minY + 1) / scale) : "0x0"
print(String(format: "read bar=%.3f far=%.3f mean=%.3f inkpx=%d box=%@", bar, far, mean, ink, box))

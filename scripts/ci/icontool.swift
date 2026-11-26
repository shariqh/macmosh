// icontool: draws the built app's icon as the system gives it, and the icon document's styles, on sheets with no
// words. CI only (.github/workflows/icon-pictures.yml, through scripts/ci/icon-pictures.sh; look step 5a, issue
// 175). It only reads: it never changes the app, starts it or registers it, and changes no setting. Never needed on
// your own Mac.
//
//   icontool <app> <out.png> <scale>     scale 1 or 2: pixels per point
//
// The sheet is 592 by 864 points, three rows 288 points high, from the top:
//   1. NSWorkspace's icon for the app, drawn with the light appearance (aqua) current, on #FFFFFF;
//   2. NSWorkspace's icon for the app, drawn with the dark appearance (darkAqua) current, on #1D1C1A;
//   3. the app's own Contents/Resources/AppIcon.icns, read as a plain image, on #F0EFED.
// Each row holds the icon at 16, 32, 64, 128 and 256 points, left to right, 16 points apart and from the edge,
// centred in the row. Row 2 shows whether AppKit draws a dark icon under a dark drawing appearance; the 16-point
// icon shows whether the system took the .icns's solid M or the tiles of Assets.car.
//
// It prints "sheet <path> <width> <height>" in pixels; per row "reps <light|dark|icns> <pixel widths>", the widths
// of the image's representations, comma separated; and for rows 1 and 2 "tile <light|dark> #RRGGBB <luminance>",
// the colour at the middle of an unlit tile. That tile is row 1 or row 3 of the M's grid, column 2: both are
// unlit, and they mirror each other, so the reading does not depend on which way a bitmap's rows run. The icon
// is drawn alone at 256 by 256 pixels for it, and the 7 by 7 pixels at (128, 162) are averaged: the grid fills
// about 80 percent of the icon's 1024 (the layer's 820) and the system's margin about 10 percent, which puts the
// tile's middle at 162 of 256 and its sides 14 pixels away. The light M's unlit tiles are near white, the dark
// M's near #34322F, so the luminance tells which M the system drew. When the sample is not opaque it missed the
// icon (a margin, or nothing drawn), and the line reads "tile <light|dark> transparent <alpha>" instead.
//
//   icontool --styles <out.png> <scale> <Default.png> <Dark.png> <ClearLight.png> <ClearDark.png> <TintedLight.png>
//            <TintedDark.png>
//
// The styles sheet: Apple's ictool renders of the icon document, 864 by 576 points, each at 256 points in a cell of
// 288. Top row on #FFFFFF: Default, ClearLight, TintedLight. Bottom row on #1D1C1A: Dark, ClearDark, TintedDark.
// It prints "styles <path> <width> <height>".
//
// It exits 1 when an input cannot be read or the PNG cannot be written, and 2 on a wrong call. Built by the
// workflow with swiftc, as a single file.
import AppKit

func fail(_ message: String, _ code: Int32 = 1) -> Never {
    print(message)
    exit(code)
}

func color(_ rgb: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
}

/// A bitmap of `width` by `height` points at `scale` pixels per point, drawn into by `draw` (origin bottom left).
func bitmap(_ width: CGFloat, _ height: CGFloat, _ scale: Int, _ draw: () -> Void) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale,
                                     pixelsHigh: Int(height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                     bitsPerPixel: 0) else { fail("icontool: cannot make a bitmap") }
    // Points, so each point is `scale` pixels. Set before the context is made, which takes its scale from it.
    rep.size = NSSize(width: width, height: height)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { fail("icontool: cannot make a bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ url: URL, _ label: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("icontool: cannot make the PNG") }
    do { try png.write(to: url) } catch { fail("icontool: cannot write \(url.path): \(error)") }
    print("\(label) \(url.path) \(rep.pixelsWide) \(rep.pixelsHigh)")
}

/// The middle of an unlit tile of the icon, drawn alone at 256 pixels (see the header).
func tile(_ name: String, _ image: NSImage) {
    let rep = bitmap(256, 256, 1) { image.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256)) }
    var sum: [CGFloat] = [0, 0, 0, 0]
    for x in 125...131 { for y in 159...165 {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        sum[0] += c.redComponent; sum[1] += c.greenComponent; sum[2] += c.blueComponent; sum[3] += c.alphaComponent } }
    let mean = sum.map { $0 / 49 }
    if mean[3] < 0.95 {
        print(String(format: "tile %@ transparent %.2f", name, mean[3]))
        return
    }
    let luminance = 0.2126 * mean[0] + 0.7152 * mean[1] + 0.0722 * mean[2]
    print(String(format: "tile %@ #%02X%02X%02X %.2f", name, Int((mean[0] * 255).rounded()),
                 Int((mean[1] * 255).rounded()), Int((mean[2] * 255).rounded()), luminance))
}

func reps(_ name: String, _ image: NSImage) {
    let widths = image.representations.map { String($0.pixelsWide) }.joined(separator: ",")
    print("reps \(name) \(widths.isEmpty ? "none" : widths)")
}

let args = CommandLine.arguments

if args.count > 1 && args[1] == "--styles" {
    guard args.count == 10, let scale = Int(args[3]), scale == 1 || scale == 2 else {
        fail("usage: icontool --styles <out.png> <1|2> <Default> <Dark> <ClearLight> <ClearDark> <TintedLight> <TintedDark>", 2)
    }
    var images: [NSImage] = []
    for path in args[4...] {
        guard let image = NSImage(contentsOf: URL(fileURLWithPath: path)) else { fail("icontool: cannot read \(path)") }
        images.append(image)
    }
    // Default, Dark, ClearLight, ClearDark, TintedLight, TintedDark: the light ones on top, the dark ones below.
    let cell: CGFloat = 288, size: CGFloat = 256
    let rep = bitmap(cell * 3, cell * 2, scale) {
        for (row, ground) in [(0, UInt32(0xFFFFFF)), (1, UInt32(0x1D1C1A))] {
            let bottom = cell * CGFloat(1 - row)
            color(ground).setFill()
            NSRect(x: 0, y: bottom, width: cell * 3, height: cell).fill()
            for column in 0..<3 {
                let rect = NSRect(x: cell * CGFloat(column) + (cell - size) / 2, y: bottom + (cell - size) / 2,
                                  width: size, height: size)
                images[column * 2 + row].draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
    }
    write(rep, URL(fileURLWithPath: args[2]), "styles")
    exit(0)
}

guard args.count == 4, let scale = Int(args[3]), scale == 1 || scale == 2 else {
    fail("usage: icontool <app> <out.png> <1|2>", 2)
}
// NSWorkspace wants a full path ("icon(forFile fullPath:)"); given a relative one it returns a generic document icon.
let appPath = URL(fileURLWithPath: args[1]).standardizedFileURL.path
var isFolder: ObjCBool = false
guard FileManager.default.fileExists(atPath: appPath, isDirectory: &isFolder), isFolder.boolValue else {
    fail("icontool: cannot read the app at \(appPath)")
}
let icnsURL = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Resources/AppIcon.icns")
guard let icns = NSImage(contentsOf: icnsURL) else { fail("icontool: cannot read \(icnsURL.path)") }

let sizes: [CGFloat] = [16, 32, 64, 128, 256]
let margin: CGFloat = 16
let rowHeight: CGFloat = 288
let width = sizes.reduce(0, +) + margin * CGFloat(sizes.count + 1)   // 592
let height = rowHeight * 3                                            // 864

/// One row; `index` 0 is the top row. AppKit's origin is the bottom left.
func drawRow(_ index: Int, ground: UInt32, image: NSImage) {
    let bottom = height - rowHeight * CGFloat(index + 1)
    color(ground).setFill()
    NSRect(x: 0, y: bottom, width: width, height: rowHeight).fill()
    var x = margin
    for size in sizes {
        let rect = NSRect(x: x, y: bottom + (rowHeight - size) / 2, width: size, height: size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        x += size + margin
    }
}

// NSWorkspace is asked once per row, so no image cached under one appearance is drawn under the other. The tile
// readings draw each image again, under the same appearance, into a bitmap of their own.
var light = NSImage(), dark = NSImage()
let sheet = bitmap(width, height, scale) {
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
        light = NSWorkspace.shared.icon(forFile: appPath)
        drawRow(0, ground: 0xFFFFFF, image: light)
    }
    NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
        dark = NSWorkspace.shared.icon(forFile: appPath)
        drawRow(1, ground: 0x1D1C1A, image: dark)
    }
    drawRow(2, ground: 0xF0EFED, image: icns)
}
reps("light", light)
reps("dark", dark)
reps("icns", icns)
NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { tile("light", light) }
NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { tile("dark", dark) }
write(sheet, URL(fileURLWithPath: args[2]), "sheet")

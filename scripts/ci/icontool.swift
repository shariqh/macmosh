// icontool: draws the built app's icon as the system gives it, on one sheet with no words. CI only
// (.github/workflows/icon-pictures.yml, through scripts/ci/icon-pictures.sh; look step 5a, issue 175). It only
// reads the app: it never changes it, starts it or registers it. Never needed on your own Mac.
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
// It prints "sheet <path> <width> <height>" in pixels, and per row "reps <light|dark|icns> <pixel widths>", the
// widths of the image's representations, comma separated. It exits 1 when the app or its .icns cannot be read or
// the PNG cannot be written, and 2 on a wrong call. Built by the workflow with swiftc, as a single file.
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let scale = Int(args[3]), scale == 1 || scale == 2 else {
    print("usage: icontool <app> <out.png> <1|2>")
    exit(2)
}
// NSWorkspace wants a full path ("icon(forFile fullPath:)"); given a relative one it returns a generic document icon.
let appPath = URL(fileURLWithPath: args[1]).standardizedFileURL.path
let outURL = URL(fileURLWithPath: args[2])

var isFolder: ObjCBool = false
guard FileManager.default.fileExists(atPath: appPath, isDirectory: &isFolder), isFolder.boolValue else {
    print("icontool: cannot read the app at \(appPath)")
    exit(1)
}
let icnsURL = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Resources/AppIcon.icns")
guard let icns = NSImage(contentsOf: icnsURL) else {
    print("icontool: cannot read \(icnsURL.path)")
    exit(1)
}

let sizes: [CGFloat] = [16, 32, 64, 128, 256]
let margin: CGFloat = 16
let rowHeight: CGFloat = 288
let width = sizes.reduce(0, +) + margin * CGFloat(sizes.count + 1)   // 592
let height = rowHeight * 3                                            // 864

func color(_ rgb: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
}

func reps(_ name: String, _ image: NSImage) {
    let widths = image.representations.map { String($0.pixelsWide) }.joined(separator: ",")
    print("reps \(name) \(widths.isEmpty ? "none" : widths)")
}

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    print("icontool: cannot make the sheet")
    exit(1)
}
// Points, so each point is `scale` pixels. Set before the context is made, which takes its scale from it.
rep.size = NSSize(width: width, height: height)
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    print("icontool: cannot make the sheet")
    exit(1)
}

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

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
// NSWorkspace is asked once per row, so no image cached under one appearance is drawn under the other.
NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
    let light = NSWorkspace.shared.icon(forFile: appPath)
    reps("light", light)
    drawRow(0, ground: 0xFFFFFF, image: light)
}
NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
    let dark = NSWorkspace.shared.icon(forFile: appPath)
    reps("dark", dark)
    drawRow(1, ground: 0x1D1C1A, image: dark)
}
reps("icns", icns)
drawRow(2, ground: 0xF0EFED, image: icns)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    print("icontool: cannot make the PNG")
    exit(1)
}
do {
    try png.write(to: outURL)
} catch {
    print("icontool: cannot write \(outURL.path): \(error)")
    exit(1)
}
print("sheet \(outURL.path) \(rep.pixelsWide) \(rep.pixelsHigh)")

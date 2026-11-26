// draw-icon: draws the app icon's three pictures from IconArt (design section 8.1), so they can be
// made again. Built and run by hand, from the repository folder:
//
//   swiftc -O -o "$TMPDIR/draw-icon" scripts/draw-icon/main.swift Sources/MacMoshKit/Look/IconArt.swift
//   "$TMPDIR/draw-icon" .
//
// It writes, in sRGB:
//   App/AppIcon.icon/Assets/m-light.png and m-dark.png   the Icon Composer document's two layers,
//                                                        1024 by 1024, opaque, square, with no mask
//   App/AppIcon-16.png                                   the solid M that build-app.sh puts in the .icns
//                                                        at 16 pixels, light only
//
// Drawn flat: a gradient inside each tile and no shadow, glow, stroke or highlight; the system adds
// its own. The pictures are committed, and nothing compares their bytes.
//
// It must be called main.swift: compiled with IconArt.swift, only a file of that name may hold
// top-level code. It uses CoreGraphics and ImageIO, and Foundation for paths; never AppKit.
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: draw-icon <repository folder>\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
let documentJSON = "App/AppIcon.icon/icon.json"
guard FileManager.default.fileExists(atPath: root.appendingPathComponent(documentJSON).path) else {
    FileHandle.standardError.write(Data("draw-icon: \(arguments[1]) has no \(documentJSON); give the repository folder\n".utf8))
    exit(1)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ rgb: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
}

func gradient(_ stops: [IconStop]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map { color($0.rgb) } as CFArray,
               locations: stops.map { CGFloat($0.location) })!
}

/// A context `size` pixels square, flipped once so that y counts down from the top, as IconArt's do.
func makeContext(size: Int, opaque: Bool) -> CGContext {
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: alpha.rawValue)!
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)
    return context
}

/// Fills whatever is clipped with `stops`, from y = top to y = bottom.
func fill(_ context: CGContext, _ stops: [IconStop], top: Int, bottom: Int) {
    context.drawLinearGradient(gradient(stops), start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func tilePath(_ cell: IconCell) -> CGPath {
    let origin = IconArt.tileOrigin(cell)
    let rect = CGRect(x: origin.x, y: origin.y, width: IconArt.tile, height: IconArt.tile)
    let radius = CGFloat(IconArt.tileRadius)
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawLayer(_ appearance: IconAppearance) -> CGImage {
    let context = makeContext(size: IconArt.canvas, opaque: true)
    fill(context, IconArt.ground(appearance), top: 0, bottom: IconArt.canvas)
    for row in 0..<IconArt.gridSize {
        for column in 0..<IconArt.gridSize {
            let cell = IconCell(row: row, column: column)
            if IconArt.isLit(cell) { continue }
            let top = IconArt.tileOrigin(cell).y
            context.saveGState()
            context.addPath(tilePath(cell))
            context.clip()
            fill(context, IconArt.unlit(appearance), top: top, bottom: top + IconArt.tile)
            context.restoreGState()
        }
    }
    // The M: one gradient over the whole grid, seen through the union of its thirteen tiles.
    context.saveGState()
    for cell in IconArt.mCells { context.addPath(tilePath(cell)) }
    context.clip()
    fill(context, IconArt.lit(appearance), top: IconArt.litTop, bottom: IconArt.litBottom)
    context.restoreGState()
    return context.makeImage()!
}

func drawSmall(_ appearance: IconAppearance) -> CGImage {
    let context = makeContext(size: IconArt.small, opaque: false)
    let body = CGRect(x: IconArt.smallBodyOrigin, y: IconArt.smallBodyOrigin,
                      width: IconArt.smallBodySize, height: IconArt.smallBodySize)
    let radius = CGFloat(IconArt.smallBodyRadius)
    context.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(color(IconArt.smallGround(appearance)))
    context.fillPath()
    // The M on whole pixels: 2 by 2 squares with antialiasing off, so it stays solid.
    context.setShouldAntialias(false)
    context.saveGState()
    for cell in IconArt.mCells {
        let origin = IconArt.smallCellOrigin(cell)
        context.addRect(CGRect(x: origin.x, y: origin.y, width: IconArt.smallCell, height: IconArt.smallCell))
    }
    context.clip()
    let mSide = IconArt.gridSize * IconArt.smallCell
    fill(context, IconArt.smallM(appearance), top: IconArt.smallMOrigin, bottom: IconArt.smallMOrigin + mSide)
    context.restoreGState()
    return context.makeImage()!
}

func write(_ image: CGImage, to relativePath: String) {
    let url = root.appendingPathComponent(relativePath)
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch {
        FileHandle.standardError.write(Data("draw-icon: cannot make the folder for \(relativePath): \(error)\n".utf8))
        exit(1)
    }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("draw-icon: cannot write \(relativePath)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("draw-icon: cannot write \(relativePath)\n".utf8))
        exit(1)
    }
    print("draw-icon: wrote \(relativePath) (\(image.width) by \(image.height))")
}

write(drawLayer(.light), to: "App/AppIcon.icon/Assets/m-light.png")
write(drawLayer(.dark), to: "App/AppIcon.icon/Assets/m-dark.png")
write(drawSmall(.light), to: "App/AppIcon-16.png")

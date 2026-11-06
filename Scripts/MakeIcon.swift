// Turns a square, full-bleed 1024×1024 artwork into a macOS app icon:
// scaled onto Apple's icon grid (824 px body, continuous-corner radius) on a
// transparent 1024 canvas, with the standard soft drop shadow.
//
//   swift Scripts/MakeIcon.swift Resources/AppIcon-source.png .build/AppIcon-1024.png
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: MakeIcon.swift <source.png> <output.png>\n".data(using: .utf8)!)
    exit(2)
}
let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("Could not read \(inputURL.path)\n".data(using: .utf8)!)
    exit(1)
}

let canvas = 1024
let body: CGFloat = 824                     // Apple's icon grid
let inset = (CGFloat(canvas) - body) / 2
let radius = body * 0.2237                  // ≈ macOS corner radius
let rect = CGRect(x: inset, y: inset, width: body, height: body)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}
ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
ctx.interpolationQuality = .high

// Rounded-rect clip (continuous corners approximated with a bezier path).
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Shadow pass: draw the silhouette with a shadow, then the artwork on top.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
ctx.addPath(path)
ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path)
ctx.clip()
// Aspect-fill the artwork into the body rect.
let aw = CGFloat(artwork.width), ah = CGFloat(artwork.height)
let scale = max(body / aw, body / ah)
let drawSize = CGSize(width: aw * scale, height: ah * scale)
let drawRect = CGRect(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2,
                      width: drawSize.width, height: drawSize.height)
ctx.draw(artwork, in: drawRect)
ctx.restoreGState()

guard let result = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("Icon written to \(outputURL.path)")

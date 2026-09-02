import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the 1024px master icon for CapsAwake: a dark rounded tile with a
// green dot (the menu-bar on state). Run via scripts/make-icon.sh.

let side = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

let margin = 90.0
let tile = CGRect(x: margin, y: margin, width: Double(side) - margin * 2, height: Double(side) - margin * 2)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 190, cornerHeight: 190, transform: nil)
ctx.addPath(tilePath)
ctx.setFillColor(CGColor(srgbRed: 0.10, green: 0.12, blue: 0.15, alpha: 1))
ctx.fillPath()

let dotCenter = CGPoint(x: Double(side) / 2, y: Double(side) / 2)
let dotRadius = 240.0
let glow = CGRect(x: dotCenter.x - dotRadius * 1.35,
                  y: dotCenter.y - dotRadius * 1.35,
                  width: dotRadius * 2.7,
                  height: dotRadius * 2.7)
ctx.setFillColor(CGColor(srgbRed: 0.13, green: 0.77, blue: 0.37, alpha: 0.35))
ctx.fillEllipse(in: glow)
ctx.setFillColor(CGColor(srgbRed: 0.13, green: 0.77, blue: 0.37, alpha: 1))
ctx.fillEllipse(in: CGRect(x: dotCenter.x - dotRadius,
                           y: dotCenter.y - dotRadius,
                           width: dotRadius * 2,
                           height: dotRadius * 2))

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write(Data("could not render icon\n".utf8))
    exit(1)
}
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let url = URL(fileURLWithPath: output) as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("could not write \(output)\n".utf8))
    exit(1)
}
print(output)

#!/usr/bin/env swift  // Generates Grove's app icon set and menu bar glyph from one drawing.
// Usage: swift scripts/make-icon.swift   (writes into Grove/Resources/Assets.xcassets)
import AppKit

let catalog = URL(fileURLWithPath: "Grove/Resources/Assets.xcassets")

/// Trunk and three branches in a 1024-unit box (origin bottom-left), ends marked by nodes.
func drawGlyph(in ctx: CGContext, trunk: CGColor, nodes: CGColor, line: CGFloat = 44, radius: CGFloat = 54) {
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(line)
    ctx.setStrokeColor(trunk)
    ctx.move(to: CGPoint(x: 512, y: 250))
    ctx.addLine(to: CGPoint(x: 512, y: 500))
    ctx.move(to: CGPoint(x: 512, y: 500))
    ctx.addCurve(
        to: CGPoint(x: 300, y: 760), control1: CGPoint(x: 512, y: 620), control2: CGPoint(x: 300, y: 610))
    ctx.move(to: CGPoint(x: 512, y: 500))
    ctx.addLine(to: CGPoint(x: 512, y: 790))
    ctx.move(to: CGPoint(x: 512, y: 500))
    ctx.addCurve(
        to: CGPoint(x: 724, y: 700), control1: CGPoint(x: 512, y: 600), control2: CGPoint(x: 724, y: 590))
    ctx.strokePath()
    ctx.setFillColor(nodes)
    for center in [(512, 250), (300, 760), (512, 790), (724, 700)] {
        ctx.fillEllipse(
            in: CGRect(
                x: CGFloat(center.0) - radius, y: CGFloat(center.1) - radius, width: radius * 2,
                height: radius * 2))
    }
}

func render(pixels: Int, draw: (CGContext) -> Void) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func appIcon(_ ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x2C6B4F), color(0x0F3324)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()
    drawGlyph(in: ctx, trunk: color(0xF4EFDC), nodes: color(0x9BE3A5))
}

func menuBarGlyph(_ ctx: CGContext) {
    // Fit the glyph's box (248...776 x 196...844) into the canvas with a little margin.
    ctx.translateBy(x: 512, y: 512)
    ctx.scaleBy(x: 0.9, y: 0.9)
    ctx.scaleBy(x: 1.45, y: 1.45)
    ctx.translateBy(x: -512, y: -520)
    drawGlyph(in: ctx, trunk: .black, nodes: .black, line: 56, radius: 70)
}

func write(_ data: Data, to path: String) throws {
    let url = catalog.appending(path: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

let info = #"{ "info" : { "version" : 1, "author" : "xcode" } }"#
try write(Data(info.utf8), to: "Contents.json")

var images: [String] = []
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        try write(render(pixels: points * scale, draw: appIcon), to: "AppIcon.appiconset/\(name)")
        images.append(
            #"{ "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)" }"#
        )
    }
}
try write(
    Data(
        #"{ "images" : [\#(images.joined(separator: ","))], "info" : { "version" : 1, "author" : "xcode" } }"#
            .utf8), to: "AppIcon.appiconset/Contents.json")

try write(render(pixels: 18, draw: menuBarGlyph), to: "MenuBarIcon.imageset/menubar@1x.png")
try write(render(pixels: 36, draw: menuBarGlyph), to: "MenuBarIcon.imageset/menubar@2x.png")
let menu =
    #"{ "images" : [ { "filename" : "menubar@1x.png", "idiom" : "universal", "scale" : "1x" }, { "filename" : "menubar@2x.png", "idiom" : "universal", "scale" : "2x" } ], "info" : { "version" : 1, "author" : "xcode" }, "properties" : { "template-rendering-intent" : "template" } }"#
try write(Data(menu.utf8), to: "MenuBarIcon.imageset/Contents.json")
print("icons written to \(catalog.path)")

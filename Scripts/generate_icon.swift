#!/usr/bin/env swift

import AppKit
import Foundation

let rootDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesDirectory = rootDirectory.appendingPathComponent("Resources", isDirectory: true)
let iconsetDirectory = resourcesDirectory.appendingPathComponent("BrowserSelector.iconset", isDirectory: true)

if FileManager.default.fileExists(atPath: iconsetDirectory.path) {
    try FileManager.default.removeItem(at: iconsetDirectory)
}
try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

struct IconVariant {
    let filename: String
    let pixels: Int
}

let variants = [
    IconVariant(filename: "icon_16x16.png", pixels: 16),
    IconVariant(filename: "icon_16x16@2x.png", pixels: 32),
    IconVariant(filename: "icon_32x32.png", pixels: 32),
    IconVariant(filename: "icon_32x32@2x.png", pixels: 64),
    IconVariant(filename: "icon_128x128.png", pixels: 128),
    IconVariant(filename: "icon_128x128@2x.png", pixels: 256),
    IconVariant(filename: "icon_256x256.png", pixels: 256),
    IconVariant(filename: "icon_256x256@2x.png", pixels: 512),
    IconVariant(filename: "icon_512x512.png", pixels: 512),
    IconVariant(filename: "icon_512x512@2x.png", pixels: 1024)
]

for variant in variants {
    let image = drawIcon(pixels: variant.pixels)
    let outputURL = iconsetDirectory.appendingPathComponent(variant.filename)
    try writePNG(image, to: outputURL)
}

print("Generated BrowserSelector.iconset")

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    rep.size = NSSize(width: pixels, height: pixels)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        return rep
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))

    let size = CGFloat(pixels)
    let scale = size / 1024.0

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: x * scale, y: y * scale)
    }

    func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            calibratedRed: red / 255,
            green: green / 255,
            blue: blue / 255,
            alpha: alpha
        )
    }

    let background = NSBezierPath(
        roundedRect: rect(64, 64, 896, 896),
        xRadius: 226 * scale,
        yRadius: 226 * scale
    )

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 34 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -16 * scale)
    shadow.set()

    let backgroundGradient = NSGradient(colors: [
        color(15, 28, 48),
        color(22, 90, 105),
        color(79, 118, 255)
    ])!
    backgroundGradient.draw(in: background, angle: 315)

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    color(255, 255, 255, 0.12).setStroke()
    background.lineWidth = 3 * scale
    background.stroke()

    let orbitalRing = NSBezierPath(ovalIn: rect(234, 226, 556, 556))
    color(255, 255, 255, 0.26).setStroke()
    orbitalRing.lineWidth = 28 * scale
    orbitalRing.stroke()

    let innerRing = NSBezierPath(ovalIn: rect(330, 322, 364, 364))
    color(255, 255, 255, 0.72).setStroke()
    innerRing.lineWidth = 24 * scale
    innerRing.stroke()

    drawArc(
        center: point(512, 504),
        radius: 300 * scale,
        startAngle: 22,
        endAngle: 118,
        strokeColor: color(97, 232, 189),
        lineWidth: 34 * scale
    )

    drawArc(
        center: point(512, 504),
        radius: 300 * scale,
        startAngle: 148,
        endAngle: 232,
        strokeColor: color(255, 194, 87),
        lineWidth: 34 * scale
    )

    drawArc(
        center: point(512, 504),
        radius: 300 * scale,
        startAngle: 266,
        endAngle: 344,
        strokeColor: color(255, 101, 133),
        lineWidth: 34 * scale
    )

    drawNode(rect(248, 638, 130, 130), fill: color(97, 232, 189), ring: color(255, 255, 255, 0.78))
    drawNode(rect(660, 628, 130, 130), fill: color(255, 194, 87), ring: color(255, 255, 255, 0.78))
    drawNode(rect(446, 226, 130, 130), fill: color(255, 101, 133), ring: color(255, 255, 255, 0.78))

    let selector = NSBezierPath()
    selector.move(to: point(430, 612))
    selector.line(to: point(664, 494))
    selector.line(to: point(566, 458))
    selector.line(to: point(632, 326))
    selector.line(to: point(548, 288))
    selector.line(to: point(486, 424))
    selector.line(to: point(420, 342))
    selector.close()

    color(255, 255, 255, 0.98).setFill()
    selector.fill()

    color(8, 24, 42, 0.38).setStroke()
    selector.lineWidth = 12 * scale
    selector.lineJoinStyle = .round
    selector.stroke()

    let centerDot = NSBezierPath(ovalIn: rect(468, 460, 88, 88))
    color(255, 255, 255, 1).setFill()
    centerDot.fill()
    color(16, 42, 68, 0.32).setStroke()
    centerDot.lineWidth = 8 * scale
    centerDot.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep

    func drawArc(
        center: NSPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        strokeColor: NSColor,
        lineWidth: CGFloat
    ) {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        strokeColor.setStroke()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.stroke()
    }

    func drawNode(_ nodeRect: NSRect, fill: NSColor, ring: NSColor) {
        let outer = NSBezierPath(ovalIn: nodeRect)
        ring.setFill()
        outer.fill()

        let inner = NSBezierPath(ovalIn: nodeRect.insetBy(dx: 20 * scale, dy: 20 * scale))
        fill.setFill()
        inner.fill()

        color(255, 255, 255, 0.35).setStroke()
        inner.lineWidth = 4 * scale
        inner.stroke()
    }
}

func writePNG(_ representation: NSBitmapImageRep, to url: URL) throws {
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "BrowserSelector.IconGeneration",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG at \(url.path)"]
        )
    }

    try data.write(to: url)
}

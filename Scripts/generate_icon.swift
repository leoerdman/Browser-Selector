#!/usr/bin/env swift

import AppKit
import Foundation

let rootDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesDirectory = rootDirectory.appendingPathComponent("Resources", isDirectory: true)
let iconsetDirectory = resourcesDirectory.appendingPathComponent("BrowserSelector.iconset", isDirectory: true)
let svgURL = resourcesDirectory.appendingPathComponent("BrowserSelector.svg")

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

guard FileManager.default.fileExists(atPath: svgURL.path) else {
    throw NSError(
        domain: "BrowserSelector.IconGeneration",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Missing SVG master icon at \(svgURL.path)"]
    )
}

print("Generated BrowserSelector.iconset")
print("Validated BrowserSelector.svg")

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
    context.imageInterpolation = .high
    context.cgContext.setShouldAntialias(true)

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

    func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(
            roundedRect: rect(x, y, width, height),
            xRadius: radius * scale,
            yRadius: radius * scale
        )
    }

    func line(_ points: [NSPoint], color strokeColor: NSColor, width: CGFloat, cap: NSBezierPath.LineCapStyle = .round) {
        guard let firstPoint = points.first else {
            return
        }

        let path = NSBezierPath()
        path.move(to: firstPoint)
        points.dropFirst().forEach { path.line(to: $0) }
        strokeColor.setStroke()
        path.lineWidth = width * scale
        path.lineCapStyle = cap
        path.lineJoinStyle = .round
        path.stroke()
    }

    let background = roundedRect(64, 64, 896, 896, radius: 224)

    NSGraphicsContext.saveGraphicsState()
    let backgroundShadow = NSShadow()
    backgroundShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    backgroundShadow.shadowBlurRadius = 34 * scale
    backgroundShadow.shadowOffset = NSSize(width: 0, height: -18 * scale)
    backgroundShadow.set()

    NSGradient(colors: [
        color(8, 16, 28),
        color(16, 57, 90),
        color(25, 118, 176),
        color(78, 211, 201)
    ])!.draw(in: background, angle: 312)
    NSGraphicsContext.restoreGraphicsState()

    color(255, 255, 255, 0.16).setStroke()
    background.lineWidth = 3 * scale
    background.stroke()

    drawSoftOrb(in: rect(178, 660, 300, 300), colors: [color(101, 232, 191, 0.32), color(101, 232, 191, 0)])
    drawSoftOrb(in: rect(640, 198, 260, 260), colors: [color(255, 201, 98, 0.22), color(255, 201, 98, 0)])

    let orbit = NSBezierPath()
    orbit.move(to: point(180, 470))
    orbit.curve(
        to: point(846, 572),
        controlPoint1: point(342, 742),
        controlPoint2: point(682, 756)
    )
    orbit.curve(
        to: point(190, 454),
        controlPoint1: point(656, 412),
        controlPoint2: point(362, 354)
    )
    color(255, 255, 255, 0.24).setStroke()
    orbit.lineWidth = 24 * scale
    orbit.lineCapStyle = .round
    orbit.stroke()

    drawGlobe()
    drawChooserPlaque()

    NSGraphicsContext.restoreGraphicsState()
    return rep

    func drawSoftOrb(in orbRect: NSRect, colors: [NSColor]) {
        guard pixels >= 128 else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: orbRect).addClip()
        NSGradient(colors: colors)!.draw(in: orbRect, relativeCenterPosition: .zero)
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawGlobe() {
        let globeRect = rect(164, 154, 696, 696)
        let globe = NSBezierPath(ovalIn: globeRect)

        NSGraphicsContext.saveGraphicsState()
        let globeShadow = NSShadow()
        globeShadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        globeShadow.shadowBlurRadius = 42 * scale
        globeShadow.shadowOffset = NSSize(width: 0, height: -20 * scale)
        globeShadow.set()
        NSGradient(colors: [
            color(12, 58, 91),
            color(17, 122, 174),
            color(55, 205, 206),
            color(164, 244, 232)
        ])!.draw(in: globe, angle: 310)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        globe.addClip()

        if pixels >= 64 {
            color(255, 255, 255, 0.24).setStroke()
            for meridianRect in [
                rect(244, 154, 536, 696),
                rect(338, 154, 348, 696),
                rect(432, 154, 160, 696)
            ] {
                let path = NSBezierPath(ovalIn: meridianRect)
                path.lineWidth = 8 * scale
                path.stroke()
            }

            color(255, 255, 255, 0.20).setStroke()
            for latitude in [314, 424, 540, 654] as [CGFloat] {
                let path = NSBezierPath()
                path.move(to: point(216, latitude))
                path.curve(
                    to: point(808, latitude),
                    controlPoint1: point(372, latitude + 52),
                    controlPoint2: point(652, latitude + 52)
                )
                path.lineWidth = 8 * scale
                path.lineCapStyle = .round
                path.stroke()
            }
        }

        let landForms: [(CGFloat, CGFloat, CGFloat, CGFloat, NSColor)] = [
            (262, 560, 210, 96, color(73, 225, 170, 0.36)),
            (540, 604, 178, 86, color(255, 206, 97, 0.27)),
            (600, 350, 180, 100, color(85, 236, 201, 0.28)),
            (286, 332, 168, 84, color(255, 106, 139, 0.24))
        ]

        if pixels >= 128 {
            for landForm in landForms {
                let land = NSBezierPath(ovalIn: rect(landForm.0, landForm.1, landForm.2, landForm.3))
                landForm.4.setFill()
                land.fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        color(255, 255, 255, 0.52).setStroke()
        globe.lineWidth = 16 * scale
        globe.stroke()

        let highlight = NSBezierPath()
        highlight.move(to: point(290, 676))
        highlight.curve(to: point(492, 794), controlPoint1: point(332, 754), controlPoint2: point(408, 802))
        color(255, 255, 255, 0.32).setStroke()
        highlight.lineWidth = 20 * scale
        highlight.lineCapStyle = .round
        highlight.stroke()
    }

    func drawChooserPlaque() {
        let plaque = roundedRect(250, 356, 524, 300, radius: 76)

        NSGraphicsContext.saveGraphicsState()
        let plaqueShadow = NSShadow()
        plaqueShadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        plaqueShadow.shadowBlurRadius = 34 * scale
        plaqueShadow.shadowOffset = NSSize(width: 0, height: -16 * scale)
        plaqueShadow.set()
        color(8, 15, 24, 0.82).setFill()
        plaque.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(colors: [
            color(255, 255, 255, 0.16),
            color(255, 255, 255, 0.04)
        ])!.draw(in: plaque, angle: 90)

        color(255, 255, 255, 0.28).setStroke()
        plaque.lineWidth = 3 * scale
        plaque.stroke()

        if pixels >= 128 {
            line(
                [
                    point(336, 588),
                    point(688, 588)
                ],
                color: color(255, 255, 255, 0.20),
                width: 7
            )

            let titleDotColors = [
                color(255, 104, 128, 0.95),
                color(255, 206, 97, 0.95),
                color(83, 226, 177, 0.95)
            ]

            for index in 0..<titleDotColors.count {
                let dot = NSBezierPath(ovalIn: rect(330 + CGFloat(index) * 28, 606, 14, 14))
                titleDotColors[index].setFill()
                dot.fill()
            }
        }

        drawBrowserTile(
            frame: rect(316, 420, 112, 112),
            fill: [color(27, 140, 238), color(77, 219, 244)],
            accent: color(255, 255, 255, 0.92)
        )
        drawBrowserTile(
            frame: rect(456, 420, 112, 112),
            fill: [color(255, 191, 75), color(255, 94, 122)],
            accent: color(255, 255, 255, 0.92)
        )
        drawBrowserTile(
            frame: rect(596, 420, 112, 112),
            fill: [color(90, 229, 167), color(44, 137, 255)],
            accent: color(255, 255, 255, 0.92)
        )
    }

    func drawBrowserTile(frame: NSRect, fill: [NSColor], accent: NSColor) {
        let tile = NSBezierPath(
            roundedRect: frame,
            xRadius: 26 * scale,
            yRadius: 26 * scale
        )

        color(255, 255, 255, 0.16).setFill()
        tile.fill()
        color(255, 255, 255, 0.22).setStroke()
        tile.lineWidth = 2 * scale
        tile.stroke()

        let browserCircleRect = frame.insetBy(dx: 20 * scale, dy: 20 * scale)
        let browserCircle = NSBezierPath(ovalIn: browserCircleRect)

        NSGraphicsContext.saveGraphicsState()
        browserCircle.addClip()
        NSGradient(colors: fill)!.draw(in: browserCircleRect, angle: 315)
        NSGraphicsContext.restoreGraphicsState()

        accent.setStroke()
        browserCircle.lineWidth = 5 * scale
        browserCircle.stroke()

        if pixels >= 64 {
            let inset = browserCircleRect.insetBy(dx: 18 * scale, dy: 18 * scale)
            let needle = NSBezierPath()
            needle.move(to: NSPoint(x: inset.midX - 6 * scale, y: inset.midY - 18 * scale))
            needle.line(to: NSPoint(x: inset.midX + 18 * scale, y: inset.midY + 22 * scale))
            accent.withAlphaComponent(0.82).setStroke()
            needle.lineWidth = 5 * scale
            needle.lineCapStyle = .round
            needle.stroke()

            let center = NSBezierPath(ovalIn: NSRect(
                x: inset.midX - 9 * scale,
                y: inset.midY - 9 * scale,
                width: 18 * scale,
                height: 18 * scale
            ))
            color(255, 255, 255, 0.88).setFill()
            center.fill()
        }
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

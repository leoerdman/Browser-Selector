import AppKit

enum StatusIconFactory {
    static func makeStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let glyphColor = NSColor.black

        glyphColor.setStroke()
        glyphColor.setFill()

        let globe = NSBezierPath(ovalIn: NSRect(x: 2.2, y: 2.1, width: 13.6, height: 13.6))
        globe.lineWidth = 1.35
        globe.stroke()

        let meridian = NSBezierPath(ovalIn: NSRect(x: 5.3, y: 2.1, width: 7.4, height: 13.6))
        meridian.lineWidth = 0.8
        meridian.stroke()

        let upperLatitude = NSBezierPath()
        upperLatitude.move(to: NSPoint(x: 3.7, y: 7.0))
        upperLatitude.curve(
            to: NSPoint(x: 14.3, y: 7.0),
            controlPoint1: NSPoint(x: 6.1, y: 5.9),
            controlPoint2: NSPoint(x: 11.9, y: 5.9)
        )
        upperLatitude.lineWidth = 0.75
        upperLatitude.lineCapStyle = .round
        upperLatitude.stroke()

        let lowerLatitude = NSBezierPath()
        lowerLatitude.move(to: NSPoint(x: 3.7, y: 11.0))
        lowerLatitude.curve(
            to: NSPoint(x: 14.3, y: 11.0),
            controlPoint1: NSPoint(x: 6.1, y: 12.1),
            controlPoint2: NSPoint(x: 11.9, y: 12.1)
        )
        lowerLatitude.lineWidth = 0.75
        lowerLatitude.lineCapStyle = .round
        lowerLatitude.stroke()

        let chooser = NSBezierPath(roundedRect: NSRect(x: 4.15, y: 6.15, width: 9.7, height: 5.7), xRadius: 1.7, yRadius: 1.7)
        chooser.lineWidth = 1.05
        chooser.stroke()

        NSBezierPath(ovalIn: NSRect(x: 5.9, y: 8.05, width: 1.25, height: 1.25)).fill()
        NSBezierPath(ovalIn: NSRect(x: 8.4, y: 8.05, width: 1.25, height: 1.25)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.9, y: 8.05, width: 1.25, height: 1.25)).fill()

        image.unlockFocus()
        image.isTemplate = true

        return image
    }
}

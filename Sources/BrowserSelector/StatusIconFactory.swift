import AppKit

enum StatusIconFactory {
    static func makeStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let ring = NSBezierPath(ovalIn: NSRect(x: 2.5, y: 2.5, width: 13, height: 13))
        ring.lineWidth = 1.7
        ring.stroke()

        let nodePath = NSBezierPath()
        nodePath.move(to: NSPoint(x: 9, y: 9))
        nodePath.line(to: NSPoint(x: 14, y: 13))
        nodePath.lineWidth = 1.5
        nodePath.stroke()

        NSBezierPath(ovalIn: NSRect(x: 7.15, y: 7.15, width: 3.7, height: 3.7)).fill()
        NSBezierPath(ovalIn: NSRect(x: 12.5, y: 11.5, width: 3.4, height: 3.4)).fill()

        image.unlockFocus()
        image.isTemplate = true

        return image
    }
}

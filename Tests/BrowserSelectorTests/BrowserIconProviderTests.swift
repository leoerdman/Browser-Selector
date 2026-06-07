import AppKit
import XCTest
@testable import BrowserSelector

final class BrowserIconProviderTests: XCTestCase {
    func testRasterizedIconProducesImmediateBitmapRepresentation() throws {
        let sourceIcon = NSImage(size: NSSize(width: 24, height: 24))
        sourceIcon.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 24, height: 24)).fill()
        sourceIcon.unlockFocus()

        let icon = try XCTUnwrap(
            BrowserIconProvider.rasterizedIcon(
                from: sourceIcon,
                displaySize: NSSize(width: 46, height: 46),
                pixelSize: 128
            )
        )

        let bitmapRepresentation = try XCTUnwrap(
            icon.representations.compactMap { $0 as? NSBitmapImageRep }.first
        )
        XCTAssertEqual(icon.size, NSSize(width: 46, height: 46))
        XCTAssertEqual(bitmapRepresentation.pixelsWide, 128)
        XCTAssertEqual(bitmapRepresentation.pixelsHigh, 128)
        XCTAssertEqual(bitmapRepresentation.size, NSSize(width: 46, height: 46))
    }
}

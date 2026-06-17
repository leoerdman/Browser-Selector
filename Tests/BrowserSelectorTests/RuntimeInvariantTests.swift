import AppKit
import XCTest
@testable import BrowserSelector

final class RuntimeInvariantTests: XCTestCase {
    func testAppIsMenuBarAgentAndNeverDockApp() throws {
        let plist = try Self.infoPlist()

        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }

    func testAppIconHasSVGMasterSource() throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let plist = try Self.infoPlist()

        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "BrowserSelector")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: projectRoot
                    .appendingPathComponent("Resources/BrowserSelector.svg")
                    .path
            )
        )
    }

    func testStatusIconIsTemplateMenuBarGlyph() {
        let image = StatusIconFactory.makeStatusIcon()

        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
        XCTAssertNotNil(image.tiffRepresentation)
    }

    private static func infoPlist() throws -> [String: Any] {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        return try XCTUnwrap(plist as? [String: Any])
    }
}

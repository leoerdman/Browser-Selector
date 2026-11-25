import XCTest
@testable import BrowserSelector

final class BrowserSelectorConstantsTests: XCTestCase {
    func testWebURLSchemesComeFromBundleURLTypesAndIgnoreNonWebSchemes() {
        let rawURLTypes: [[String: Any]] = [
            [
                "CFBundleURLSchemes": ["HTTP", "browser-selector"]
            ],
            [
                "CFBundleURLSchemes": ["https", "http"]
            ]
        ]

        XCTAssertEqual(
            BrowserSelectorConstants.webURLSchemes(from: rawURLTypes),
            ["http", "https"]
        )
    }

    func testWebContentTypesComeFromBundleDocumentTypesAndIgnoreNonWebTypes() {
        let rawDocumentTypes: [[String: Any]] = [
            [
                "LSItemContentTypes": ["PUBLIC.HTML", "public.plain-text"]
            ],
            [
                "LSItemContentTypes": ["public.xhtml", "public.html"]
            ]
        ]

        XCTAssertEqual(
            BrowserSelectorConstants.webContentTypes(from: rawDocumentTypes),
            ["public.html"]
        )
    }

    func testIsWebURLOnlyAcceptsHTTPAndHTTPS() throws {
        XCTAssertTrue(BrowserSelectorConstants.isWebURL(try XCTUnwrap(URL(string: "HTTP://example.com"))))
        XCTAssertTrue(BrowserSelectorConstants.isWebURL(try XCTUnwrap(URL(string: "https://example.com"))))
        XCTAssertFalse(BrowserSelectorConstants.isWebURL(try XCTUnwrap(URL(string: "file:///tmp/test.html"))))
        XCTAssertFalse(BrowserSelectorConstants.isWebURL(try XCTUnwrap(URL(string: "browser-selector://test"))))
    }

    func testLocalWebDocumentsAreFilesOfClaimedContentTypes() throws {
        let claimed = BrowserSelectorConstants.claimedDocumentContentTypes(from: [
            ["LSItemContentTypes": ["public.html"]],
            ["LSItemContentTypes": ["PUBLIC.XHTML", "public.html"]]
        ])

        XCTAssertEqual(claimed, ["public.html", "public.xhtml"])
        XCTAssertTrue(BrowserSelectorConstants.isLocalWebDocument(
            URL(fileURLWithPath: "/Users/me/Programming - Main/PROJECT-MAP.html"), claimedContentTypes: claimed
        ))
        XCTAssertTrue(BrowserSelectorConstants.isLocalWebDocument(
            URL(fileURLWithPath: "/tmp/page.xhtml"), claimedContentTypes: claimed
        ))
        XCTAssertFalse(BrowserSelectorConstants.isLocalWebDocument(
            URL(fileURLWithPath: "/tmp/notes.txt"), claimedContentTypes: claimed
        ))
        XCTAssertFalse(BrowserSelectorConstants.isLocalWebDocument(
            try XCTUnwrap(URL(string: "https://example.com/page.html")), claimedContentTypes: claimed
        ))
    }
}

import XCTest
@testable import BrowserSelector

final class BrowserLaunchPlanTests: XCTestCase {
    func testPlansTryAppleScriptFirstAndAlwaysEndWithLaunchServices() {
        XCTAssertEqual(
            BrowserLaunchPlan.strategies(chromiumLike: true),
            [.chromiumNewTab, .openLocation, .launchServices]
        )
        XCTAssertEqual(
            BrowserLaunchPlan.strategies(chromiumLike: false),
            [.openLocation, .launchServices]
        )
    }

    func testLaunchServicesIsTheOnlyStepWithoutAppleEventsAuthorization() {
        XCTAssertTrue(BrowserLaunchStrategy.chromiumNewTab.requiresAppleEventsAuthorization)
        XCTAssertTrue(BrowserLaunchStrategy.openLocation.requiresAppleEventsAuthorization)
        XCTAssertFalse(BrowserLaunchStrategy.launchServices.requiresAppleEventsAuthorization)
    }

    func testGenericAppleScriptFailureTriesNextStrategy() {
        let plan = BrowserLaunchPlan.strategies(chromiumLike: true)[...]

        XCTAssertEqual(
            Array(BrowserLaunchPlan.strategies(after: plan, appleEventsDenied: false)),
            [.openLocation, .launchServices]
        )
    }

    /// Regression: -1743 used to end the launch with an error alert and the link was lost.
    func testDeniedAppleEventsSkipsStraightToLaunchServicesInsteadOfDroppingTheLink() {
        for chromiumLike in [true, false] {
            let plan = BrowserLaunchPlan.strategies(chromiumLike: chromiumLike)[...]

            XCTAssertEqual(
                Array(BrowserLaunchPlan.strategies(after: plan, appleEventsDenied: true)),
                [.launchServices],
                "chromiumLike=\(chromiumLike)"
            )
        }
    }

    func testFailedLaunchServicesEndsThePlan() {
        XCTAssertTrue(BrowserLaunchPlan.strategies(after: [.launchServices], appleEventsDenied: false).isEmpty)
        XCTAssertTrue(BrowserLaunchPlan.strategies(after: [.launchServices], appleEventsDenied: true).isEmpty)
    }

    func testAppleEventsNotPermittedMatchesErrAEEventNotPermitted() {
        XCTAssertEqual(BrowserLaunchPlan.appleEventsNotPermittedErrorNumber, -1743)
    }
}

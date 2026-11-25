import Foundation

/// One way to hand a link to a browser. SSOT for the launch order and for which steps depend on Apple Events.
enum BrowserLaunchStrategy: Equatable, CustomStringConvertible {
    /// AppleScript: new tab in the front window of a Chromium-family browser.
    case chromiumNewTab
    /// AppleScript: `open location` in the browser.
    case openLocation
    /// `open -b <bundle id> <url>`: LaunchServices delivers the URL through the browser's own `kAEGetURL`
    /// handler. Needs no Automation (TCC) permission, so it is always the terminal step of a plan.
    case launchServices

    var requiresAppleEventsAuthorization: Bool {
        switch self {
        case .chromiumNewTab, .openLocation:
            return true
        case .launchServices:
            return false
        }
    }

    var description: String {
        switch self {
        case .chromiumNewTab:
            return "chromiumNewTab"
        case .openLocation:
            return "openLocation"
        case .launchServices:
            return "launchServices"
        }
    }
}

enum BrowserLaunchPlan {
    /// `errAEEventNotPermitted`: TCC refused to let this app send Apple Events to the target. Returned instantly and
    /// without a prompt when the user denied Automation access, and also when the target was updated in place while
    /// running (e.g. Chrome's background updater), because its on-disk signature no longer matches the running process.
    static let appleEventsNotPermittedErrorNumber = -1743

    static func strategies(chromiumLike: Bool) -> [BrowserLaunchStrategy] {
        chromiumLike
            ? [.chromiumNewTab, .openLocation, .launchServices]
            : [.openLocation, .launchServices]
    }

    /// Strategies still worth trying after the head of `remaining` failed. A denied Apple Events authorization
    /// fails every other Apple Events strategy identically, so those are skipped instead of re-hitting TCC;
    /// the link is never dropped because the plan always ends with `.launchServices`.
    static func strategies(
        after remaining: ArraySlice<BrowserLaunchStrategy>,
        appleEventsDenied: Bool
    ) -> ArraySlice<BrowserLaunchStrategy> {
        let rest = remaining.dropFirst()
        guard appleEventsDenied else {
            return rest
        }

        return ArraySlice(rest.filter { !$0.requiresAppleEventsAuthorization })
    }
}

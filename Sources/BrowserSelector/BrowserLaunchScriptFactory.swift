import Foundation

enum BrowserLaunchScriptFactory {
    static func chromiumNewTabScript(bundleIdentifier: String, urlString: String) -> String {
        let browserID = appleScriptLiteral(bundleIdentifier)
        let targetURL = appleScriptLiteral(urlString)

        return """
        using terms from application id \(browserID)
        tell application id \(browserID)
            activate
            if (count of windows) = 0 then make new window
            tell front window
                set newTab to make new tab at end of tabs with properties {URL:\(targetURL)}
                set active tab index to (count of tabs)
            end tell
        end tell
        end using terms from
        """
    }

    static func openLocationScript(bundleIdentifier: String, urlString: String) -> String {
        let browserID = appleScriptLiteral(bundleIdentifier)
        let targetURL = appleScriptLiteral(urlString)

        return """
        tell application id \(browserID)
            activate
            open location \(targetURL)
        end tell
        """
    }

    static func appleScriptLiteral(_ value: String) -> String {
        let escapedValue = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")

        return "\"\(escapedValue)\""
    }
}

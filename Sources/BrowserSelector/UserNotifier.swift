import AppKit

enum UserNotifier {
    static func showError(title: String, message: String) {
        showAlert(style: .critical, title: title, message: message)
    }

    static func showInfo(title: String, message: String) {
        showAlert(style: .informational, title: title, message: message)
    }

    private static func showAlert(style: NSAlert.Style, title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = style
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")

            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

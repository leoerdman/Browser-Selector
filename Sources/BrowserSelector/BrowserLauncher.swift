import AppKit
import Foundation

final class BrowserLauncher {
    func open(_ url: URL, in browser: Browser, completion: @escaping (Result<Void, Error>) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.allowsRunningApplicationSubstitution = true

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: browser.bundleURL,
            configuration: configuration
        ) { _, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}

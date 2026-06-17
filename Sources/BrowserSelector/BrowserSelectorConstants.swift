import Foundation

enum BrowserSelectorConstants {
    private static let defaultWebURLSchemes = ["http", "https"]
    private static let defaultWebContentTypes = ["public.html"]
    private static let supportedWebURLSchemes = Set(defaultWebURLSchemes)
    private static let supportedWebContentTypes = Set(defaultWebContentTypes)

    static var webURLSchemes: [String] {
        let declaredSchemes = webURLSchemes(
            from: Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
        )

        return declaredSchemes.isEmpty ? defaultWebURLSchemes : declaredSchemes
    }

    static var webContentTypes: [String] {
        let declaredContentTypes = webContentTypes(
            from: Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes")
        )

        return declaredContentTypes.isEmpty ? defaultWebContentTypes : declaredContentTypes
    }

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        return Set(webURLSchemes).contains(scheme)
    }

    static func webURLSchemes(from rawURLTypes: Any?) -> [String] {
        guard let urlTypes = rawURLTypes as? [[String: Any]] else {
            return []
        }

        var schemes: [String] = []
        for urlType in urlTypes {
            guard let declaredSchemes = urlType["CFBundleURLSchemes"] as? [String] else {
                continue
            }

            schemes.append(
                contentsOf: declaredSchemes
                    .map { $0.lowercased() }
                    .filter { supportedWebURLSchemes.contains($0) }
            )
        }

        return schemes.reduce(into: []) { uniqueSchemes, scheme in
            guard !uniqueSchemes.contains(scheme) else {
                return
            }

            uniqueSchemes.append(scheme)
        }
    }

    static func webContentTypes(from rawDocumentTypes: Any?) -> [String] {
        guard let documentTypes = rawDocumentTypes as? [[String: Any]] else {
            return []
        }

        var contentTypes: [String] = []
        for documentType in documentTypes {
            guard let declaredContentTypes = documentType["LSItemContentTypes"] as? [String] else {
                continue
            }

            contentTypes.append(
                contentsOf: declaredContentTypes
                    .map { $0.lowercased() }
                    .filter { supportedWebContentTypes.contains($0) }
            )
        }

        return contentTypes.reduce(into: []) { uniqueContentTypes, contentType in
            guard !uniqueContentTypes.contains(contentType) else {
                return
            }

            uniqueContentTypes.append(contentType)
        }
    }
}

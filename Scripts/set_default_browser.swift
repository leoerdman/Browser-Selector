import AppKit
import CoreServices
import Foundation

private struct AppInfoPlist: Decodable {
    let urlTypes: [URLType]
    let documentTypes: [DocumentType]?

    enum CodingKeys: String, CodingKey {
        case urlTypes = "CFBundleURLTypes"
        case documentTypes = "CFBundleDocumentTypes"
    }
}

private struct URLType: Decodable {
    let schemes: [String]

    enum CodingKeys: String, CodingKey {
        case schemes = "CFBundleURLSchemes"
    }
}

private struct DocumentType: Decodable {
    let contentTypes: [String]?

    enum CodingKeys: String, CodingKey {
        case contentTypes = "LSItemContentTypes"
    }
}

private let webSchemes = Set(["http", "https"])
private let webContentTypes = Set(["public.html"])

private func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

private func fail(_ message: String, code: Int32 = 1) -> Never {
    writeStandardError("\(message)\n")
    exit(code)
}

private func loadInfoPlist(from infoPlistURL: URL) -> AppInfoPlist {
    let data: Data
    do {
        data = try Data(contentsOf: infoPlistURL)
    } catch {
        fail("Unable to read Info.plist at \(infoPlistURL.path): \(error.localizedDescription)", code: 66)
    }

    do {
        return try PropertyListDecoder().decode(AppInfoPlist.self, from: data)
    } catch {
        fail("Unable to parse Info.plist at \(infoPlistURL.path): \(error.localizedDescription)", code: 65)
    }
}

private func loadWebURLSchemes(from infoPlistURL: URL) -> [String] {
    let infoPlist = loadInfoPlist(from: infoPlistURL)
    let schemes = infoPlist.urlTypes
        .flatMap(\.schemes)
        .map { $0.lowercased() }
        .filter { webSchemes.contains($0) }

    let uniqueSchemes = schemes.reduce(into: [String]()) { result, scheme in
        guard !result.contains(scheme) else {
            return
        }

        result.append(scheme)
    }
    guard !uniqueSchemes.isEmpty else {
        fail("Info.plist does not declare http/https CFBundleURLSchemes.", code: 65)
    }

    return uniqueSchemes
}

private func loadWebContentTypes(from infoPlistURL: URL) -> [String] {
    let infoPlist = loadInfoPlist(from: infoPlistURL)
    let contentTypes = (infoPlist.documentTypes ?? [])
        .flatMap { $0.contentTypes ?? [] }
        .map { $0.lowercased() }
        .filter { webContentTypes.contains($0) }

    let uniqueContentTypes = contentTypes.reduce(into: [String]()) { result, contentType in
        guard !result.contains(contentType) else {
            return
        }

        result.append(contentType)
    }

    guard !uniqueContentTypes.isEmpty else {
        fail("Info.plist does not declare public.html CFBundleDocumentTypes.", code: 65)
    }

    return uniqueContentTypes
}

private func defaultHandlerBundleIdentifier(for scheme: String) -> String? {
    guard let url = URL(string: "\(scheme)://browser-selector.local"),
          let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url)
    else {
        return nil
    }

    return Bundle(url: applicationURL)?.bundleIdentifier
}

private func defaultRoleHandlerBundleIdentifier(for contentType: String) -> String? {
    LSCopyDefaultRoleHandlerForContentType(contentType as NSString, .viewer)?
        .takeRetainedValue() as String?
}

let expectedArgumentCount = 3
if CommandLine.arguments.count == expectedArgumentCount,
   CommandLine.arguments[1] == "--print-web-schemes"
{
    let infoPlistURL = URL(fileURLWithPath: CommandLine.arguments[2])
    print(loadWebURLSchemes(from: infoPlistURL).joined(separator: "\n"))
    exit(0)
}

if CommandLine.arguments.count == expectedArgumentCount,
   CommandLine.arguments[1] == "--print-web-content-types"
{
    let infoPlistURL = URL(fileURLWithPath: CommandLine.arguments[2])
    print(loadWebContentTypes(from: infoPlistURL).joined(separator: "\n"))
    exit(0)
}

if CommandLine.arguments.count == expectedArgumentCount,
   CommandLine.arguments[1] == "--print-default-handlers"
{
    let infoPlistURL = URL(fileURLWithPath: CommandLine.arguments[2])
    for scheme in loadWebURLSchemes(from: infoPlistURL) {
        print("\(scheme)=\(defaultHandlerBundleIdentifier(for: scheme) ?? "nil")")
    }
    for contentType in loadWebContentTypes(from: infoPlistURL) {
        print("\(contentType)=\(defaultRoleHandlerBundleIdentifier(for: contentType) ?? "nil")")
    }
    exit(0)
}

guard CommandLine.arguments.count == expectedArgumentCount else {
    fail(
        """
        Usage: set-default-browser <bundle-identifier> <info-plist-path>
               set-default-browser --print-web-schemes <info-plist-path>
               set-default-browser --print-web-content-types <info-plist-path>
               set-default-browser --print-default-handlers <info-plist-path>
        """,
        code: 64
    )
}

let bundleIdentifier = CommandLine.arguments[1]
let infoPlistURL = URL(fileURLWithPath: CommandLine.arguments[2])
let schemes = loadWebURLSchemes(from: infoPlistURL)
let contentTypes = loadWebContentTypes(from: infoPlistURL)
var requestedSystemConfirmation = false

for scheme in schemes {
    let status = LSSetDefaultHandlerForURLScheme(
        scheme as NSString,
        bundleIdentifier as NSString
    )

    if status == -54 {
        requestedSystemConfirmation = true
        continue
    }

    guard status == noErr else {
        fail("LaunchServices returned \(status) while setting \(scheme) handler.")
    }
}

for contentType in contentTypes {
    let status = LSSetDefaultRoleHandlerForContentType(
        contentType as NSString,
        .viewer,
        bundleIdentifier as NSString
    )

    if status == -54 {
        requestedSystemConfirmation = true
        continue
    }

    guard status == noErr else {
        fail("LaunchServices returned \(status) while setting \(contentType) viewer.")
    }
}

func currentDefaultHandlerMismatches() -> [String] {
    var mismatches: [String] = []
    for scheme in schemes {
        let actualHandler = defaultHandlerBundleIdentifier(for: scheme)

        guard actualHandler == bundleIdentifier else {
            mismatches.append("\(scheme)=\(actualHandler ?? "nil")")
            continue
        }
    }

    for contentType in contentTypes {
        let actualHandler = defaultRoleHandlerBundleIdentifier(for: contentType)

        guard actualHandler == bundleIdentifier else {
            mismatches.append("\(contentType)=\(actualHandler ?? "nil")")
            continue
        }
    }

    return mismatches
}

var mismatches = currentDefaultHandlerMismatches()
if requestedSystemConfirmation {
    let deadline = Date().addingTimeInterval(120)
    while !mismatches.isEmpty && Date() < deadline {
        Thread.sleep(forTimeInterval: 1)
        mismatches = currentDefaultHandlerMismatches()
    }
}

guard mismatches.isEmpty else {
    if requestedSystemConfirmation {
        fail("Default browser confirmation was not applied before timeout: \(mismatches.joined(separator: ", ")).")
    } else {
        fail("Default browser was not applied: \(mismatches.joined(separator: ", ")).")
    }
}

let handledTypes = (schemes + contentTypes).joined(separator: ", ")
print("Default web handler: \(bundleIdentifier) for \(handledTypes)")

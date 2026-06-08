#!/usr/bin/env swift

import CoreServices
import AppKit
import Foundation

let expectedArgumentCount = 2
guard CommandLine.arguments.count == expectedArgumentCount else {
    FileHandle.standardError.write(
        Data("Usage: set_default_browser.swift <bundle-identifier>\n".utf8)
    )
    exit(64)
}

let bundleIdentifier = CommandLine.arguments[1]
let schemes = ["http", "https"]

for scheme in schemes {
    let status = LSSetDefaultHandlerForURLScheme(
        scheme as NSString,
        bundleIdentifier as NSString
    )

    guard status == noErr || status == -54 else {
        FileHandle.standardError.write(
            Data("LaunchServices returned \(status) while setting \(scheme) handler.\n".utf8)
        )
        exit(1)
    }
}

var mismatches: [String] = []
for scheme in schemes {
    let url = URL(string: "\(scheme)://browser-selector.local")!
    let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url)
    let actualHandler = applicationURL.flatMap { Bundle(url: $0)?.bundleIdentifier }

    guard actualHandler == bundleIdentifier else {
        mismatches.append("\(scheme)=\(actualHandler ?? "nil")")
        continue
    }
}

guard mismatches.isEmpty else {
    FileHandle.standardError.write(
        Data("Default browser was not applied: \(mismatches.joined(separator: ", ")).\n".utf8)
    )
    exit(1)
}

print("Default web handler: \(bundleIdentifier)")

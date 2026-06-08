import AppKit
import Foundation
import UniformTypeIdentifiers

protocol BrowserIconProviding {
    func icon(forApplicationAt applicationURL: URL) -> NSImage
}

final class BrowserIconProvider: BrowserIconProviding {
    static let shared = BrowserIconProvider()

    private enum Metrics {
        static let displaySize = NSSize(width: 46, height: 46)
        static let pixelSize = 128
    }

    private let workspace: NSWorkspace
    private let cache = NSCache<NSString, NSImage>()

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        cache.countLimit = 128
    }

    func icon(forApplicationAt applicationURL: URL) -> NSImage {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync {
                self.icon(forApplicationAt: applicationURL)
            }
        }

        let cacheKey = applicationURL.resolvingSymlinksInPath().standardizedFileURL.path as NSString
        if let cachedIcon = cache.object(forKey: cacheKey) {
            return cachedIcon
        }

        let sourceIcon = workspace.icon(forFile: applicationURL.path)
        let icon = Self.rasterizedIcon(from: sourceIcon)
            ?? fallbackIcon()
        cache.setObject(icon, forKey: cacheKey)

        return icon
    }

    static func rasterizedIcon(
        from sourceIcon: NSImage,
        displaySize: NSSize = Metrics.displaySize,
        pixelSize: Int = Metrics.pixelSize
    ) -> NSImage? {
        guard pixelSize > 0,
              displaySize.width > 0,
              displaySize.height > 0,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelSize,
                pixelsHigh: pixelSize,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              )
        else {
            return nil
        }

        bitmap.size = displaySize
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(origin: .zero, size: displaySize))
        sourceIcon.draw(
            in: NSRect(origin: .zero, size: displaySize),
            from: .zero,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        let icon = NSImage(size: displaySize)
        icon.addRepresentation(bitmap)
        icon.cacheMode = .always
        icon.isTemplate = false

        return icon
    }

    private func fallbackIcon() -> NSImage {
        let sourceIcon = workspace.icon(for: .applicationBundle)
        if let icon = Self.rasterizedIcon(from: sourceIcon) {
            return icon
        }

        return NSImage(size: Metrics.displaySize)
    }
}

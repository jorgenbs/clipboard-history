import AppKit
import ClipboardCore

/// Polls the general pasteboard's `changeCount` and records new clips that pass the capture filter.
final class PasteboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let store: ClipStore
    private let settings: Settings
    private var timer: Timer?
    private var lastChangeCount: Int
    /// Change count produced by our own write when pasting; never record it.
    private var ownChangeCount: Int?

    init(store: ClipStore, settings: Settings) {
        self.store = store
        self.settings = settings
        // Don't record whatever was on the clipboard before launch.
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Call right after the app itself writes to the pasteboard.
    func noteOwnWrite() {
        ownChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard count != ownChangeCount, !settings.isPaused else { return }
        capture()
    }

    private func capture() {
        guard let items = pasteboard.pasteboardItems, let item = items.first else { return }
        // Only the first item is recorded, but sensitive markers are honoured on any item.
        let markers = items.dropFirst()
            .flatMap { $0.types.map(\.rawValue) }
            .filter(PBType.sensitiveMarkers.contains)
        let types = item.types.map(\.rawValue) + markers

        let frontmost = NSWorkspace.shared.frontmostApplication
        var sourceIDs: [String] = []
        if let id = frontmost?.bundleIdentifier { sourceIDs.append(id) }
        // nspasteboard.org: apps may declare the real source app on the pasteboard.
        let declaredSource = item.string(forType: NSPasteboard.PasteboardType(PBType.source))
            ?? pasteboard.string(forType: NSPasteboard.PasteboardType(PBType.source))
        if let declaredSource, !declaredSource.isEmpty { sourceIDs.append(declaredSource) }

        let filter = CaptureFilter(ignoredBundleIDs: settings.ignoredBundleIDs)
        guard case let .record(wanted) = filter.decide(types: types, sourceBundleIDs: sourceIDs) else { return }

        let reps: [(type: String, data: Data)] = wanted.compactMap { type in
            item.data(forType: NSPasteboard.PasteboardType(type)).map { (type, $0) }
        }

        let sourceApp: SourceApp
        if let declaredSource, !declaredSource.isEmpty, declaredSource != frontmost?.bundleIdentifier {
            sourceApp = SourceApp(bundleID: declaredSource, name: AppInfo.name(for: declaredSource))
        } else {
            sourceApp = SourceApp(bundleID: frontmost?.bundleIdentifier, name: frontmost?.localizedName)
        }

        guard var clip = ClipFactory.make(representations: reps, source: sourceApp) else { return }
        if clip.kind == .image, let data = clip.representations.first?.data, let image = NSImage(data: data) {
            let rep = image.representations.first
            clip.pixelWidth = rep?.pixelsWide ?? Int(image.size.width)
            clip.pixelHeight = rep?.pixelsHigh ?? Int(image.size.height)
            clip.thumbnail = image.pngThumbnail(maxPixels: 96)
        }
        store.add(clip)
    }
}

extension NSImage {
    func pngThumbnail(maxPixels: CGFloat) -> Data? {
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxPixels / max(size.width, size.height))
        let target = NSSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}

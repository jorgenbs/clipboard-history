import AppKit
import ClipboardCore

/// Avoids re-reading and re-decoding image blobs on every SwiftUI render.
enum ImageCache {
    private static let thumbnails: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.countLimit = 300
        return cache
    }()
    private static var preview: (id: UUID, image: NSImage)?

    static func thumbnail(for clip: Clip, store: ClipStore) -> NSImage? {
        if let cached = thumbnails.object(forKey: clip.id as NSUUID) { return cached }
        guard let data = store.thumbnail(for: clip), let image = NSImage(data: data) else { return nil }
        thumbnails.setObject(image, forKey: clip.id as NSUUID)
        return image
    }

    /// Keeps only the most recently previewed full-size image in memory.
    static func previewImage(for clip: Clip, store: ClipStore) -> NSImage? {
        if let preview, preview.id == clip.id { return preview.image }
        guard let data = store.representations(for: clip).first?.data, let image = NSImage(data: data) else { return nil }
        preview = (clip.id, image)
        return image
    }
}

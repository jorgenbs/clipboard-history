import Combine
import Foundation

/// Ordered (newest first) clip history persisted to disk.
///
/// Layout under `directory`:
///   index.json            – `[Clip]` metadata
///   blobs/<uuid>/<n>      – raw pasteboard data, n = index into `clip.types`
///   blobs/<uuid>/thumb    – optional PNG thumbnail for image clips
///
/// Not thread safe: use from the main thread.
public final class ClipStore: ObservableObject {
    @Published public private(set) var clips: [Clip] = []

    public var limit: Int {
        didSet { if limit != oldValue { trim(); save() } }
    }

    private let directory: URL
    private let blobsDirectory: URL
    private let indexURL: URL
    private let fm = FileManager.default
    private let now: () -> Date

    public init(directory: URL, limit: Int, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.blobsDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        self.indexURL = directory.appendingPathComponent("index.json")
        self.limit = max(1, limit)
        self.now = now
        try? fm.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
        load()
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipboardHistory", isDirectory: true)
    }

    // MARK: - Mutations

    /// Inserts a new clip at the top. If a clip with the same content already exists it is
    /// moved to the top instead (and its source/date refreshed). Returns the stored clip.
    @discardableResult
    public func add(_ new: NewClip) -> Clip {
        if let index = clips.firstIndex(where: { $0.contentHash == new.contentHash }) {
            var existing = clips.remove(at: index)
            existing.date = now()
            existing.sourceBundleID = new.source.bundleID ?? existing.sourceBundleID
            existing.sourceAppName = new.source.name ?? existing.sourceAppName
            clips.insert(existing, at: 0)
            save()
            return existing
        }

        let clip = Clip(
            id: UUID(),
            date: now(),
            kind: new.kind,
            text: String(new.fullText.prefix(Clip.indexTextLimit)),
            textLength: new.fullText.count,
            contentHash: new.contentHash,
            sourceBundleID: new.source.bundleID,
            sourceAppName: new.source.name,
            types: new.representations.map(\.type),
            byteSize: new.byteSize,
            pixelWidth: new.pixelWidth,
            pixelHeight: new.pixelHeight,
            hasThumbnail: new.thumbnail != nil
        )
        let dir = blobDirectory(for: clip.id)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for (i, rep) in new.representations.enumerated() {
                try rep.data.write(to: dir.appendingPathComponent(String(i)), options: .atomic)
            }
            if let thumb = new.thumbnail {
                try thumb.write(to: dir.appendingPathComponent("thumb"), options: .atomic)
            }
        } catch {
            NSLog("ClipboardHistory: failed to write clip blobs: \(error)")
        }
        clips.insert(clip, at: 0)
        trim()
        save()
        return clip
    }

    /// Moves a clip to the top (used after pasting it).
    public func promote(id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var clip = clips.remove(at: index)
        clip.date = now()
        clips.insert(clip, at: 0)
        save()
    }

    public func delete(id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips.remove(at: index)
        try? fm.removeItem(at: blobDirectory(for: id))
        save()
    }

    public func clear() {
        clips.removeAll()
        try? fm.removeItem(at: blobsDirectory)
        try? fm.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
        save()
    }

    // MARK: - Reading data

    public func representations(for clip: Clip) -> [(type: String, data: Data)] {
        let dir = blobDirectory(for: clip.id)
        return clip.types.enumerated().compactMap { i, type in
            (try? Data(contentsOf: dir.appendingPathComponent(String(i)))).map { (type, $0) }
        }
    }

    public func data(for clip: Clip, type: String) -> Data? {
        guard let i = clip.types.firstIndex(of: type) else { return nil }
        return try? Data(contentsOf: blobDirectory(for: clip.id).appendingPathComponent(String(i)))
    }

    /// Full plain text (the index copy may be truncated).
    public func fullText(for clip: Clip) -> String {
        guard clip.textLength > clip.text.count else { return clip.text }
        for type in [PBType.plainText, PBType.url] {
            if let data = data(for: clip, type: type), let s = String(data: data, encoding: .utf8) {
                return s
            }
        }
        return clip.text
    }

    public func thumbnail(for clip: Clip) -> Data? {
        guard clip.hasThumbnail else { return nil }
        return try? Data(contentsOf: blobDirectory(for: clip.id).appendingPathComponent("thumb"))
    }

    // MARK: - Persistence

    private func blobDirectory(for id: UUID) -> URL {
        blobsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func trim() {
        guard clips.count > limit else { return }
        let removed = clips[limit...]
        for clip in removed { try? fm.removeItem(at: blobDirectory(for: clip.id)) }
        clips.removeLast(clips.count - limit)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            clips = try decoder.decode([Clip].self, from: data)
        } catch {
            NSLog("ClipboardHistory: could not read history index, starting fresh: \(error)")
            clips = []
        }
        trim()
        removeOrphanBlobs()
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(clips).write(to: indexURL, options: .atomic)
        } catch {
            NSLog("ClipboardHistory: failed to save history index: \(error)")
        }
    }

    /// Blob folders without an index entry (e.g. after a crash mid-write).
    private func removeOrphanBlobs() {
        let known = Set(clips.map(\.id.uuidString))
        let entries = (try? fm.contentsOfDirectory(atPath: blobsDirectory.path)) ?? []
        for name in entries where !known.contains(name) {
            try? fm.removeItem(at: blobsDirectory.appendingPathComponent(name))
        }
    }
}

import CryptoKit
import Foundation

public enum ClipKind: String, Codable, Sendable {
    case text
    case richText
    case url
    case image
}

/// One history entry. The index only keeps metadata and a (possibly truncated) copy of the
/// text for listing and searching. The actual pasteboard data lives in blob files.
public struct Clip: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var date: Date
    public var kind: ClipKind
    /// Plain text (truncated to `Clip.indexTextLimit`). Empty for images.
    public var text: String
    /// Full length of the plain text in characters (0 for images).
    public var textLength: Int
    public var contentHash: String
    public var sourceBundleID: String?
    public var sourceAppName: String?
    /// Pasteboard types stored as blobs, in write-back order.
    public var types: [String]
    public var byteSize: Int
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var hasThumbnail: Bool

    public static let indexTextLimit = 10_000

    /// First non-empty line, used as the row title.
    public var title: String {
        if kind == .image { return "img" }
        let line = text.split(whereSeparator: \.isNewline)
            .first(where: { !$0.allSatisfy(\.isWhitespace) }) ?? ""
        return line.trimmingCharacters(in: .whitespaces)
    }
}

public struct SourceApp: Equatable, Sendable {
    public var bundleID: String?
    public var name: String?
    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// A freshly captured clip, before it's stored.
public struct NewClip: Sendable {
    public var kind: ClipKind
    public var fullText: String
    public var contentHash: String
    public var representations: [(type: String, data: Data)]
    public var source: SourceApp
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var thumbnail: Data?

    public var byteSize: Int { representations.reduce(0) { $0 + $1.data.count } }
}

public enum ClipFactory {
    public static let defaultMaxBytes = 10 * 1024 * 1024

    /// Builds a `NewClip` from the representations chosen by `CaptureFilter`.
    /// Returns nil for empty or oversized content.
    public static func make(
        representations: [(type: String, data: Data)],
        source: SourceApp,
        maxBytes: Int = defaultMaxBytes
    ) -> NewClip? {
        let all = representations.filter { !$0.data.isEmpty }
        let textReps = all.filter { PBType.textTypes.contains($0.type) }

        func string(_ type: String) -> String? {
            textReps.first(where: { $0.type == type }).flatMap { String(data: $0.data, encoding: .utf8) }
        }
        let candidate = string(PBType.plainText) ?? string(PBType.url)
        guard let text = candidate, !text.allSatisfy({ $0.isWhitespace || $0.isNewline }) else {
            // No usable text: fall back to the image, if any.
            guard let image = all.first(where: { PBType.imageTypes.contains($0.type) }),
                  image.data.count <= maxBytes else { return nil }
            return NewClip(
                kind: .image, fullText: "",
                contentHash: "img:" + sha256(image.data),
                representations: [image], source: source
            )
        }
        let reps = textReps
        guard reps.reduce(0, { $0 + $1.data.count }) <= maxBytes else { return nil }

        let kind: ClipKind
        if isURL(text) {
            kind = .url
        } else if reps.contains(where: { $0.type == PBType.rtf || $0.type == PBType.html }) {
            kind = .richText
        } else {
            kind = .text
        }
        // Hash only the plain text so the same text copied from different apps (with different
        // formatting attached) collapses into one entry.
        return NewClip(
            kind: kind, fullText: text,
            contentHash: "txt:" + sha256(Data(text.utf8)),
            representations: reps, source: source
        )
    }

    static func isURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased()
        else { return false }
        return ["http", "https", "ftp", "mailto", "file"].contains(scheme) && (url.host != nil || scheme == "mailto")
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

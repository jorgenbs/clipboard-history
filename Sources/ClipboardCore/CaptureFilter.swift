import Foundation

public enum SkipReason: Equatable, Sendable {
    case sensitiveMarker(String)
    case ignoredApp(String)
    case file
    case unsupported
}

public enum CaptureDecision: Equatable, Sendable {
    case skip(SkipReason)
    /// Record the clip, reading only these pasteboard types.
    case record(types: [String])
}

/// Decides whether a pasteboard change should be recorded, and which representations to keep.
public struct CaptureFilter: Sendable {
    public var ignoredBundleIDs: Set<String>

    public init(ignoredBundleIDs: Set<String>) {
        self.ignoredBundleIDs = ignoredBundleIDs
    }

    /// - Parameters:
    ///   - types: the pasteboard types of the first pasteboard item.
    ///   - sourceBundleIDs: every bundle ID that may have produced the copy (the frontmost app,
    ///     plus the `org.nspasteboard.source` value if present). If any of them is ignored, skip.
    public func decide(types: [String], sourceBundleIDs: [String]) -> CaptureDecision {
        if let marker = PBType.sensitiveMarkers.first(where: types.contains) {
            return .skip(.sensitiveMarker(marker))
        }
        if let ignored = sourceBundleIDs.first(where: ignoredBundleIDs.contains) {
            return .skip(.ignoredApp(ignored))
        }

        let image = PBType.imageTypes.first(where: types.contains)
        let texts = PBType.textTypes.filter(types.contains)

        if types.contains(PBType.fileURL) {
            // Finder copies carry the file name as text and the file icon as an image. Never record.
            // Other apps (Preview, Photos, screenshot tools) may attach a file reference next to real
            // image data: keep the image, drop the file reference.
            if sourceBundleIDs.contains(PBType.finderBundleID) { return .skip(.file) }
            if let image { return .record(types: [image]) }
            return .skip(.file)
        }

        // Text and image can both be present (e.g. a cell copied from a spreadsheet, or an image
        // with an empty caption). ClipFactory keeps the text if it's non-empty, otherwise the image.
        var wanted = texts.contains(PBType.plainText) || texts.contains(PBType.url) ? texts : []
        if let image { wanted.append(image) }
        return wanted.isEmpty ? .skip(.unsupported) : .record(types: wanted)
    }
}

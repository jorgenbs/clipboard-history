import AppKit
import ClipboardCore
import SwiftUI

struct PreviewPane: View {
    let clip: Clip?
    let store: ClipStore

    var body: some View {
        if let clip {
            VStack(spacing: 0) {
                content(for: clip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                PreviewFooter(clip: clip)
            }
        } else {
            Text("No clip selected")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(for clip: Clip) -> some View {
        switch clip.kind {
        case .image:
            ImagePreview(clip: clip, store: store)
                .padding(16)
        case .text, .url, .richText:
            TextPreview(clip: clip, store: store)
        }
    }
}

struct ImagePreview: View {
    let clip: Clip
    let store: ClipStore

    var body: some View {
        if let image = ImageCache.previewImage(for: clip, store: store) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(
                    maxWidth: clip.pixelWidth.map { CGFloat($0) } ?? .infinity,
                    maxHeight: clip.pixelHeight.map { CGFloat($0) } ?? .infinity
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(clip.id)
        } else {
            Text("Image data missing").foregroundStyle(.secondary)
        }
    }
}

/// NSTextView-backed preview: handles very long text and rich text well.
struct TextPreview: NSViewRepresentable {
    let clip: Clip
    let store: ClipStore

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.drawsBackground = false
            text.textContainerInset = NSSize(width: 12, height: 12)
            text.isAutomaticLinkDetectionEnabled = false
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard context.coordinator.shownID != clip.id,
              let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.shownID = clip.id

        let content: NSAttributedString
        if clip.kind == .richText, let rtf = store.data(for: clip, type: PBType.rtf),
           let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            // Rich text keeps its own colors, so show it on a paper-like background to stay legible in dark mode.
            content = attributed
            textView.drawsBackground = true
            textView.backgroundColor = .white
            scroll.drawsBackground = true
            scroll.backgroundColor = .white
        } else {
            let font: NSFont = clip.kind == .url
                ? .systemFont(ofSize: 13)
                : .monospacedSystemFont(ofSize: 12, weight: .regular)
            content = NSAttributedString(
                string: store.fullText(for: clip),
                attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            )
            textView.drawsBackground = false
            scroll.drawsBackground = false
        }
        textView.textStorage?.setAttributedString(content)
        textView.scroll(.zero)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var shownID: UUID? }
}

struct PreviewFooter: View {
    let clip: Clip

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            AppIconView(bundleID: clip.sourceBundleID, size: 14)
            Text(clip.sourceAppName ?? "Unknown app")
            Text("·")
            Text(Self.dateFormatter.string(from: clip.date))
            Spacer()
            Text(sizeDescription)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private var sizeDescription: String {
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(clip.byteSize), countStyle: .file)
        if clip.kind == .image {
            if let w = clip.pixelWidth, let h = clip.pixelHeight { return "\(w)×\(h) · \(bytes)" }
            return bytes
        }
        let chars = clip.textLength.formatted()
        return "\(chars) character\(clip.textLength == 1 ? "" : "s")"
    }
}

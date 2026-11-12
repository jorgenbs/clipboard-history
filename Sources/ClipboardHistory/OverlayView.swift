import AppKit
import ClipboardCore
import SwiftUI

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                SearchField(model: model)
                    .frame(height: 30)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                Divider()
                ClipList(model: model)
            }
            .frame(width: 320)

            Divider()

            PreviewPane(clip: model.selected, store: model.store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: OverlayController.size.width, height: OverlayController.size.height)
    }
}

// MARK: - Search field

struct SearchField: NSViewRepresentable {
    @ObservedObject var model: OverlayModel

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.placeholderString = "Search clipboard history"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        model.searchField = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.query { field.stringValue = model.query }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: OverlayModel
        init(model: OverlayModel) { self.model = model }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            model.query = field.stringValue
        }
    }
}

// MARK: - List

struct ClipList: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        if model.results.isEmpty {
            VStack {
                Spacer()
                Text(model.query.isEmpty ? "Nothing copied yet" : "No matches")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, clip in
                            ClipRow(
                                clip: clip, index: index, store: model.store,
                                isSelected: clip.id == model.selectedID, now: model.now
                            )
                            .id(clip.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.onPaste(clip) }
                            .onTapGesture { model.selectedID = clip.id }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.selectedID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
    }
}

struct ClipRow: View {
    let clip: Clip
    let index: Int
    let store: ClipStore
    let isSelected: Bool
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(bundleID: clip.sourceBundleID)
            if clip.kind == .image {
                ThumbnailView(clip: clip, store: store)
                Text("img")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.2)))
                if let w = clip.pixelWidth, let h = clip.pixelHeight {
                    Text("\(w)×\(h)").foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            } else {
                Text(clip.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            Text(RelativeTime.string(for: clip.date, now: now))
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor : .clear))
    }
}

struct AppIconView: View {
    let bundleID: String?
    var size: CGFloat = 16

    var body: some View {
        if let icon = AppInfo.icon(for: bundleID) {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "doc.on.clipboard").frame(width: size, height: size).foregroundStyle(.secondary)
        }
    }
}

struct ThumbnailView: View {
    let clip: Clip
    let store: ClipStore

    var body: some View {
        if let image = ImageCache.thumbnail(for: clip, store: store) {
            Image(nsImage: image)
                .resizable().scaledToFit()
                .frame(width: 24, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

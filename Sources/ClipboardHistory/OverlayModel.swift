import AppKit
import ClipboardCore
import Combine

/// State behind the overlay: the search query, filtered results and selection.
final class OverlayModel: ObservableObject {
    @Published var query = ""
    @Published var selectedID: UUID?
    @Published private(set) var results: [Clip] = []
    /// Reference time for relative timestamps; refreshed each time the overlay opens.
    @Published private(set) var now = Date()

    let store: ClipStore
    weak var searchField: NSTextField?
    var onPaste: (Clip) -> Void = { _ in }

    private var lastQuery = ""
    private var cancellables: Set<AnyCancellable> = []

    init(store: ClipStore) {
        self.store = store
        Publishers.CombineLatest(store.$clips, $query)
            .sink { [weak self] clips, query in self?.update(clips: clips, query: query) }
            .store(in: &cancellables)
    }

    var selected: Clip? {
        guard let selectedID else { return nil }
        return results.first(where: { $0.id == selectedID })
    }

    private var selectedIndex: Int? {
        selectedID.flatMap { id in results.firstIndex(where: { $0.id == id }) }
    }

    private func update(clips: [Clip], query: String) {
        let previousIndex = selectedIndex
        results = ClipSearch.filter(clips, query: query)
        if query != lastQuery {
            lastQuery = query
            selectedID = results.first?.id
        } else if selectedID == nil || !results.contains(where: { $0.id == selectedID }) {
            // Selected clip disappeared (deleted/trimmed): keep the same position.
            let index = min(previousIndex ?? 0, results.count - 1)
            selectedID = index >= 0 ? results[index].id : nil
        }
    }

    func reset() {
        now = Date()
        searchField?.stringValue = ""
        query = ""
        selectedID = results.first?.id
    }

    func move(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = selectedIndex ?? -1
        let next = max(0, min(results.count - 1, current + delta))
        selectedID = results[next].id
    }

    func pasteSelected() {
        if let selected { onPaste(selected) } else { NSSound.beep() }
    }

    func paste(at index: Int) {
        guard results.indices.contains(index) else { NSSound.beep(); return }
        onPaste(results[index])
    }

    func deleteSelected() {
        guard let selectedID else { return }
        store.delete(id: selectedID)
    }
}

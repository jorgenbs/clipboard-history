import Foundation
import Testing
@testable import ClipboardCore

final class ClipStoreTests {
    let dir: URL
    var clock = Date(timeIntervalSince1970: 1_000_000)

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipStoreTests-\(UUID().uuidString)")
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    func makeStore(limit: Int = 500) -> ClipStore {
        ClipStore(directory: dir, limit: limit, now: { [unowned self] in
            clock = clock.addingTimeInterval(1)
            return clock
        })
    }

    func text(_ s: String, app: String? = "com.example.app") -> NewClip {
        ClipFactory.make(representations: [(PBType.plainText, Data(s.utf8))], source: SourceApp(bundleID: app, name: app))!
    }

    @Test func addsNewestFirst() {
        let store = makeStore()
        store.add(text("one"))
        store.add(text("two"))
        #expect(store.clips.map(\.text) == ["two", "one"])
    }

    @Test func duplicateMovesToTopInsteadOfAdding() {
        let store = makeStore()
        let first = store.add(text("one"))
        store.add(text("two"))
        let again = store.add(text("one", app: "com.other"))
        #expect(store.clips.map(\.text) == ["one", "two"])
        #expect(again.id == first.id)
        #expect(store.clips[0].sourceBundleID == "com.other")
    }

    @Test func trimsToLimitAndDeletesBlobs() throws {
        let store = makeStore(limit: 2)
        let oldest = store.add(text("a"))
        store.add(text("b"))
        store.add(text("c"))
        #expect(store.clips.map(\.text) == ["c", "b"])
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("blobs/\(oldest.id.uuidString)").path))
    }

    @Test func loweringLimitTrims() {
        let store = makeStore()
        for s in ["a", "b", "c", "d"] { store.add(text(s)) }
        store.limit = 2
        #expect(store.clips.map(\.text) == ["d", "c"])
    }

    @Test func persistsAcrossInstances() {
        let store = makeStore()
        let clip = store.add(text("persist me"))
        let reopened = makeStore()
        #expect(reopened.clips.map(\.id) == [clip.id])
        #expect(reopened.representations(for: reopened.clips[0]).first?.data == Data("persist me".utf8))
    }

    @Test func promoteAndDelete() {
        let store = makeStore()
        let a = store.add(text("a"))
        let b = store.add(text("b"))
        store.promote(id: a.id)
        #expect(store.clips.map(\.id) == [a.id, b.id])
        store.delete(id: a.id)
        #expect(store.clips.map(\.id) == [b.id])
    }

    @Test func clearRemovesEverything() {
        let store = makeStore()
        store.add(text("a"))
        store.clear()
        #expect(store.clips.isEmpty)
        #expect(makeStore().clips.isEmpty)
    }

    @Test func longTextIsTruncatedInIndexButFullOnDisk() {
        let store = makeStore()
        let long = String(repeating: "x", count: Clip.indexTextLimit + 50)
        let clip = store.add(text(long))
        #expect(clip.text.count == Clip.indexTextLimit)
        #expect(store.fullText(for: clip) == long)
    }
}

struct ClipFactoryTests {
    let source = SourceApp(bundleID: nil, name: nil)

    @Test func detectsURL() {
        let clip = ClipFactory.make(representations: [(PBType.plainText, Data(" https://example.com/a?b=1\n".utf8))], source: source)
        #expect(clip?.kind == .url)
    }

    @Test func detectsRichText() {
        let clip = ClipFactory.make(representations: [(PBType.plainText, Data("hi".utf8)), (PBType.rtf, Data("{\\rtf1 hi}".utf8))], source: source)
        #expect(clip?.kind == .richText)
    }

    @Test func plainTextWithSpacesIsNotURL() {
        let clip = ClipFactory.make(representations: [(PBType.plainText, Data("see https://example.com".utf8))], source: source)
        #expect(clip?.kind == .text)
    }

    @Test func skipsWhitespaceOnly() {
        #expect(ClipFactory.make(representations: [(PBType.plainText, Data("  \n ".utf8))], source: source) == nil)
    }

    @Test func skipsOversized() {
        let big = Data(count: 11)
        #expect(ClipFactory.make(representations: [(PBType.png, big)], source: source, maxBytes: 10) == nil)
    }

    @Test func textWinsOverImageAndDropsImageData() {
        let clip = ClipFactory.make(representations: [(PBType.plainText, Data("cell".utf8)), (PBType.png, Data([1, 2, 3]))], source: source)
        #expect(clip?.kind == .text)
        #expect(clip?.representations.map(\.type) == [PBType.plainText])
    }

    @Test func emptyTextFallsBackToImage() {
        let clip = ClipFactory.make(representations: [(PBType.plainText, Data(" ".utf8)), (PBType.png, Data([1, 2, 3]))], source: source)
        #expect(clip?.kind == .image)
    }

    @Test func oversizedImageDoesNotBlockText() {
        let clip = ClipFactory.make(representations: [(PBType.plainText, Data("hi".utf8)), (PBType.png, Data(count: 100))], source: source, maxBytes: 10)
        #expect(clip?.kind == .text)
    }

    @Test func imageHashIgnoresSource() {
        let data = Data([1, 2, 3])
        let a = ClipFactory.make(representations: [(PBType.png, data)], source: SourceApp(bundleID: "a", name: nil))
        let b = ClipFactory.make(representations: [(PBType.png, data)], source: SourceApp(bundleID: "b", name: nil))
        #expect(a?.kind == .image)
        #expect(a?.contentHash == b?.contentHash)
    }
}

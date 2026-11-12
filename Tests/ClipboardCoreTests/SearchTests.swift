import Foundation
import Testing
@testable import ClipboardCore

struct SearchTests {
    func clip(_ text: String, kind: ClipKind = .text, app: String? = nil) -> Clip {
        Clip(id: UUID(), date: Date(), kind: kind, text: text, textLength: text.count, contentHash: UUID().uuidString,
             sourceBundleID: nil, sourceAppName: app, types: [], byteSize: 0, pixelWidth: nil, pixelHeight: nil, hasThumbnail: false)
    }

    @Test func emptyQueryReturnsAll() {
        let clips = [clip("a"), clip("b")]
        #expect(ClipSearch.filter(clips, query: "  ").count == 2)
    }

    @Test func caseInsensitiveSubstring() {
        let clips = [clip("Hello World"), clip("goodbye")]
        #expect(ClipSearch.filter(clips, query: "WORLD").map(\.text) == ["Hello World"])
    }

    @Test func imagesMatchImgAndAppName() {
        let img = clip("", kind: .image, app: "Preview")
        #expect(ClipSearch.matches(img, query: "img"))
        #expect(ClipSearch.matches(img, query: "ima"))
        #expect(ClipSearch.matches(img, query: "prev"))
        #expect(!ClipSearch.matches(img, query: "xyz"))
    }

    @Test func titleIsFirstNonEmptyLine() {
        #expect(clip("\n\n  first line  \nsecond").title == "first line")
        #expect(clip("", kind: .image).title == "img")
    }
}

struct RelativeTimeTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let now = ISO8601DateFormatter().date(from: "2026-11-12T15:00:00Z")!

    @Test func formats() {
        func s(_ offset: TimeInterval) -> String { RelativeTime.string(for: now.addingTimeInterval(-offset), now: now, calendar: calendar) }
        #expect(s(10) == "now")
        #expect(s(180) == "3m")
        #expect(s(2 * 3600) == "2h")
        #expect(s(20 * 3600) == "Yesterday")
        #expect(s(3 * 86400) == "3d")
    }
}

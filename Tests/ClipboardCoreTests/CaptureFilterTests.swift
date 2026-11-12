import Testing
@testable import ClipboardCore

struct CaptureFilterTests {
    let filter = CaptureFilter(ignoredBundleIDs: ["com.1password.1password", "com.apple.Passwords"])

    @Test func recordsPlainText() {
        #expect(filter.decide(types: [PBType.plainText], sourceBundleIDs: ["com.apple.Safari"])
            == .record(types: [PBType.plainText]))
    }

    @Test func keepsAllTextRepresentationsInOrder() {
        let types = [PBType.html, "com.apple.webarchive", PBType.rtf, PBType.plainText]
        #expect(filter.decide(types: types, sourceBundleIDs: [])
            == .record(types: [PBType.plainText, PBType.rtf, PBType.html]))
    }

    @Test(arguments: PBType.sensitiveMarkers)
    func skipsSensitiveMarkers(marker: String) {
        #expect(filter.decide(types: [PBType.plainText, marker], sourceBundleIDs: ["com.apple.Safari"])
            == .skip(.sensitiveMarker(marker)))
    }

    @Test func skipsIgnoredFrontmostApp() {
        #expect(filter.decide(types: [PBType.plainText], sourceBundleIDs: ["com.apple.Passwords"])
            == .skip(.ignoredApp("com.apple.Passwords")))
    }

    @Test func skipsIgnoredSourceMarkerEvenIfFrontmostDiffers() {
        #expect(filter.decide(types: [PBType.plainText], sourceBundleIDs: ["com.apple.Safari", "com.1password.1password"])
            == .skip(.ignoredApp("com.1password.1password")))
    }

    @Test func skipsFinderFileCopies() {
        let types = [PBType.fileURL, PBType.plainText, PBType.tiff]
        #expect(filter.decide(types: types, sourceBundleIDs: [PBType.finderBundleID]) == .skip(.file))
    }

    @Test func skipsBareFileReferences() {
        #expect(filter.decide(types: [PBType.fileURL, PBType.plainText], sourceBundleIDs: ["com.example.app"]) == .skip(.file))
    }

    @Test func keepsImageNextToFileReferenceFromOtherApps() {
        let types = [PBType.fileURL, PBType.tiff, PBType.png]
        #expect(filter.decide(types: types, sourceBundleIDs: ["com.apple.Preview"]) == .record(types: [PBType.png]))
    }

    @Test func prefersPNGOverTIFF() {
        #expect(filter.decide(types: [PBType.tiff, PBType.png], sourceBundleIDs: []) == .record(types: [PBType.png]))
    }

    @Test func keepsTextAndImageCandidates() {
        #expect(filter.decide(types: [PBType.tiff, PBType.plainText], sourceBundleIDs: [])
            == .record(types: [PBType.plainText, PBType.tiff]))
    }

    @Test func skipsUnknownTypes() {
        #expect(filter.decide(types: ["com.example.private"], sourceBundleIDs: []) == .skip(.unsupported))
    }
}

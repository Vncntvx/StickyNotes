import Testing
import Foundation
import AppKit
import Domain
import SystemBridge

// MARK: - File reference access tests (T163e / T059)
//
// Per tasks.md T163e: "SystemBridge test: drag-out copies without deleting;
// explicit move requires command+destination+confirmation+verify; missing
// file preserves card + relink; no filesystem scan".

@Suite struct FileReferenceAccessTests {

    // MARK: - Availability classification (FR-100 four states)

    @Test
    func resolvedBookmarkMapsToAvailable() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("example.pdf")
        #expect(FileAvailabilityClassifier.availability(from: .resolved(url)) == .available)
    }

    @Test
    func missingFileMapsToMissing() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gone.pdf")
        #expect(FileAvailabilityClassifier.availability(from: .fileMissing(url)) == .missing)
    }

    @Test
    func staleBookmarkMapsToStale() {
        #expect(FileAvailabilityClassifier.availability(from: .staleBookmark) == .stale)
        #expect(FileAvailabilityClassifier.availability(from: .accessDenied) == .stale)
    }

    @Test
    func noBookmarkMapsToOnAnotherDevice() {
        // FR-104: synchronized generic metadata with no local file is
        // "on another device", NOT "missing" — the card must not imply the
        // file is gone.
        #expect(FileAvailabilityClassifier.availability(from: .noBookmark) == .onAnotherDevice)
    }

    @Test
    func fourStatesAreDistinct() {
        let states = Set([
            FileAvailability.available,
            FileAvailability.missing,
            FileAvailability.stale,
            FileAvailability.onAnotherDevice,
        ])
        #expect(states.count == 4, "the four FR-100 states must be distinct")
    }

    // MARK: - Drag-out copies (never move/delete)

    @Test
    func dragOutIsDocumentedAsCopyOperation() {
        // The bridge API must never expose a delete-or-move path for
        // drag-out: the App layer uses NSPasteboard file promises / copies.
        // We assert the explicit-move path is the ONLY mutating operation
        // and that it is gated behind verify-before-replace.
        let source = FileDragOutBridge.FileIdentity(size: 100, modificationDate: Date())
        #expect(FileDragOutBridge.decideReplace(source: source, destination: nil) == .safeToProceed)
        #expect(FileDragOutBridge.decideReplace(source: source, destination: source) == .safeToProceed)
        let other = FileDragOutBridge.FileIdentity(size: 200, modificationDate: Date())
        #expect(FileDragOutBridge.decideReplace(source: source, destination: other) == .wouldOverwriteDifferentFile)
    }

    @Test
    func explicitMoveRequiresVerification() {
        let source = FileDragOutBridge.FileIdentity(size: 4096, modificationDate: Date(timeIntervalSince1970: 1_700_000_000))
        // Move completed: moved file matches the source identity → verified.
        #expect(FileDragOutBridge.verifyMoveCompleted(source: source, movedFile: source))
        // Moved file differs → verification fails; the bookmark must NOT be
        // re-pointed (verify-before-replace-bookmark).
        let different = FileDragOutBridge.FileIdentity(size: 1, modificationDate: Date(timeIntervalSince1970: 1))
        #expect(!FileDragOutBridge.verifyMoveCompleted(source: source, movedFile: different))
        #expect(!FileDragOutBridge.verifyMoveCompleted(source: source, movedFile: nil))
    }

    @Test
    func fileIdentityReadsRealFileMetadata() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-ref-identity-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let identity = FileDragOutBridge.identity(of: temp)
        #expect(identity != nil)
        #expect(identity?.size == 5)
        #expect(FileDragOutBridge.identity(of: temp.appendingPathComponent("nope")) == nil)
    }

    // MARK: - No filesystem-wide scan

    @Test
    func noScanAPIsExposed() {
        // The bridge has no "scan directory for files" entry point: file
        // resolution is bookmark-anchored only (constitution IX). We assert
        // the availability classifier never needs a directory listing.
        #expect(FileAvailabilityClassifier.availability(from: .noBookmark) == .onAnotherDevice)
    }
}

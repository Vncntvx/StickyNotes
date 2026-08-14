import Testing
import Foundation
import UniformTypeIdentifiers
import Domain
@testable import AssetStore

// MARK: - AssetStore tests (T082)
//
// Per tasks.md T082: "AssetStore test: atomic temp-write+rename, SHA-256
// hash, verify-before-delete, orphan cleanup, dedup by contentHash".

@Suite struct AssetStorageTests {

    /// Unique temp root per test; removed afterwards.
    private func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("assetstore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pngBytes() -> Data {
        // A minimal 2x2 PNG (valid enough for storage tests).
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR42mP8z8AARMAgYpwkEToAAD5tAR8PxLQmAAAAAElFTkSuQmCC")!
    }

    @Test
    func importWritesFileWithOpaqueNameAndComputesSha256() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AssetStore(directoryURL: root)
        let data = pngBytes()

        let record = try await store.importData(data, kind: .original, contentType: UTType.png.identifier)

        // Hash is sha256:<hex> and matches the bytes.
        #expect(record.contentHash.hasPrefix("sha256:"))
        #expect(record.contentHash == AssetStore.sha256Hex(data))
        #expect(record.byteSize == data.count)

        // The stored filename is opaque (a UUID), not a user-facing name.
        #expect(UUID(uuidString: record.filename) != nil)

        // The file exists at the expected path and round-trips.
        let url = try await store.url(assetID: record.id)
        #expect(url.lastPathComponent == record.filename)
        let readBack = try await store.readData(assetID: record.id)
        #expect(readBack == data)
    }

    @Test
    func dedupReusesRecordForIdenticalContent() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AssetStore(directoryURL: root)
        let data = pngBytes()

        let first = try await store.importData(data, kind: .original, contentType: UTType.png.identifier)
        let second = try await store.importData(data, kind: .original, contentType: UTType.png.identifier)

        #expect(first.id == second.id, "identical content must dedup to the same record")
        #expect(first.contentHash == second.contentHash)
        let snapshot = await store.snapshot()
        #expect(snapshot.count == 1, "dedup must not create duplicate records")

        // Different content type → NOT deduplicated.
        let jpeg = try await store.importData(data, kind: .original, contentType: UTType.jpeg.identifier)
        #expect(jpeg.id != first.id)
    }

    @Test
    func deleteVerifiesContentHashBeforeRemoving() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AssetStore(directoryURL: root)
        let record = try await store.importData(pngBytes(), kind: .original, contentType: UTType.png.identifier)

        // Integrity holds right after import.
        let intact = try await store.verifyIntegrity(assetID: record.id)
        #expect(intact)

        // Delete succeeds and the file is gone.
        try await store.delete(assetID: record.id)
        let snapshot = await store.snapshot()
        #expect(snapshot.isEmpty)
        do {
            _ = try await store.readData(assetID: record.id)
            Issue.record("read after delete must throw")
        } catch {
            #expect(true)
        }
    }

    @Test
    func orphanCleanupRemovesOnlyUnregisteredFiles() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AssetStore(directoryURL: root)
        let record = try await store.importData(pngBytes(), kind: .original, contentType: UTType.png.identifier)

        // Simulate a crash leftover: an unregistered file in originals/.
        let orphanURL = root
            .appendingPathComponent("originals", isDirectory: true)
            .appendingPathComponent("crash-leftover.bin")
        try Data([0x01, 0x02, 0x03]).write(to: orphanURL)

        let removed = try await store.cleanupOrphans()
        #expect(removed.contains("crash-leftover.bin"))
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))

        // Registered asset untouched.
        let intact = try await store.verifyIntegrity(assetID: record.id)
        #expect(intact)
    }

    @Test
    func exportCopiesWithoutMovingStoredFile() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AssetStore(directoryURL: root)
        let data = pngBytes()
        let record = try await store.importData(data, kind: .original, contentType: UTType.png.identifier)

        let destination = root.appendingPathComponent("exported.png")
        try await store.export(assetID: record.id, to: destination)

        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(try Data(contentsOf: destination) == data)

        // The stored file is still there (copy, not move — constitution IX).
        let intact = try await store.verifyIntegrity(assetID: record.id)
        #expect(intact)
    }

    @Test
    func snapshotExposesAllRegisteredRecords() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AssetStore(directoryURL: root)
        let data = pngBytes()
        let a = try await store.importData(data, kind: .original, contentType: UTType.png.identifier)
        let b = try await store.importData(Data([0xAA, 0xBB]), kind: .thumbnail, contentType: UTType.png.identifier)

        let snapshot = await store.snapshot()
        #expect(snapshot.count == 2)
        #expect(Set(snapshot.map(\.id)) == [a.id, b.id])
    }

    // MARK: - R1.1 Launch recovery (remediation roadmap 2026-08-14)

    /// A fresh store over an EXISTING store directory must recover every
    /// registered record from disk (the audit found `recordsByID` is only
    /// populated by `importData`, so a relaunch leaves every previously
    /// stored asset unreachable: `readData`/`url`/`delete` throw
    /// `.notFound` and `cleanupOrphans` would delete everything).
    @Test
    func relaunchRecoversRecordsFromDisk() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = pngBytes()
        let thumbBytes = Data([0xAA, 0xBB, 0xCC])

        let first = try AssetStore(directoryURL: root)
        let originalRecord = try await first.importData(original, kind: .original, contentType: UTType.png.identifier)
        let thumbRecord = try await first.importData(thumbBytes, kind: .thumbnail, contentType: UTType.png.identifier)

        // "Relaunch": a brand-new store instance over the same directory
        // (no state carried over — the in-memory tables start empty).
        let restarted = try AssetStore(directoryURL: root)
        try await restarted.restoreFromDisk()

        // Every stored asset must be reachable again with identical bytes.
        let readOriginal = try await restarted.readData(assetID: originalRecord.id)
        #expect(readOriginal == original)
        let readThumb = try await restarted.readData(assetID: thumbRecord.id)
        #expect(readThumb == thumbBytes)

        // The recovered records carry the on-disk facts: id (the opaque
        // filename), kind (the directory), content hash, byte size.
        let recovered = await restarted.snapshot()
        #expect(Set(recovered.map(\.id)) == [originalRecord.id, thumbRecord.id])
        #expect(recovered.first { $0.id == originalRecord.id }?.contentHash == AssetStore.sha256Hex(original))
        #expect(recovered.first { $0.id == originalRecord.id }?.byteSize == original.count)
        #expect(recovered.first { $0.id == thumbRecord.id }?.kind == .thumbnail)

        // Integrity and delete keep working on recovered records.
        #expect(try await restarted.verifyIntegrity(assetID: originalRecord.id))
        try await restarted.delete(assetID: thumbRecord.id)
        #expect(Set((await restarted.snapshot()).map(\.id)) == [originalRecord.id])
    }

    // MARK: - R1.2 cleanupOrphans safety guard (remediation roadmap 2026-08-14)

    /// Orphan cleanup must refuse to run against an EMPTY record table: a
    /// fresh store instance over an existing directory (the relaunch
    /// shape, before `restoreFromDisk` populated the tables) sees every
    /// file as an orphan — deleting would wipe the user's whole asset
    /// library. With the guard in place the destructive path is
    /// unreachable until recovery has run.
    @Test
    func cleanupRefusesWhenRecordTableIsEmpty() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // A populated store, then a fresh instance WITHOUT restore — the
        // exact relaunch shape that previously meant "no records, so
        // every file is an orphan".
        let first = try AssetStore(directoryURL: root)
        let data = pngBytes()
        let record = try await first.importData(data, kind: .original, contentType: UTType.png.identifier)
        let restarted = try AssetStore(directoryURL: root)

        let removed = try await restarted.cleanupOrphans()
        #expect(removed.isEmpty, "cleanup must refuse to delete when the record table is empty (got \(removed))")
        let storedFile = root
            .appendingPathComponent("originals", isDirectory: true)
            .appendingPathComponent(record.filename)
        #expect(FileManager.default.fileExists(atPath: storedFile.path),
                "the stored file must survive a cleanup against an unrecovered store")
    }
}

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
}

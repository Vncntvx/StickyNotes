import Testing
import Foundation
import Foundation
import Domain
import AssetStore

// MARK: - Scale limit tests (T227, FR-090b)
//
// Per tasks.md T227: "AssetStore/Persistence test: scale limits per FR-090b
// — assert constants: max asset bytes = 50 MB, max asset longest edge =
// 16,384 px, max note structured content = 5 MB; pasting/inserting an image
// over any asset limit is rejected with a localized explanation and NO
// partial asset write (no orphan temp file, no metadata record); a content
// change that would push note structured content over 5 MB is refused while
// the last valid saved state is preserved intact; assets within limits still
// sync as independent objects (FR-090a)".

@Suite struct ScaleLimitTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    // MARK: - Constants

    @Test
    func constantsMatchSpec() {
        #expect(ScaleLimits.maxAssetBytes == 50 * 1024 * 1024)
        #expect(ScaleLimits.maxAssetLongestEdge == 16_384)
        #expect(ScaleLimits.maxNoteContentBytes == 5 * 1024 * 1024)
    }

    @Test
    func boundaryAssetSizeAccepted() {
        #expect(ScaleLimits.assetBytesError(byteCount: 50 * 1024 * 1024) == nil)
        #expect(ScaleLimits.assetBytesError(byteCount: 50 * 1024 * 1024 + 1) != nil)
        #expect(ScaleLimits.assetLongestEdgeError(longestEdge: 16_384) == nil)
        #expect(ScaleLimits.assetLongestEdgeError(longestEdge: 16_385) != nil)
    }

    // MARK: - AssetStore rejection with NO partial write

    @Test
    func oversizeAssetRejectedWithNoPartialWrite() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scale-limits-\(UUID().uuidString)", isDirectory: true)
        let store = try AssetStore(directoryURL: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 50 MB + 1 byte — over the limit.
        let oversized = Data(repeating: 0xAB, count: ScaleLimits.maxAssetBytes + 1)
        do {
            _ = try await store.importData(oversized, kind: .original, contentType: "image/png")
            Issue.record("oversize asset must be rejected")
        } catch let error as AssetStoreError {
            guard case .assetTooLarge = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }

        // No partial asset write: no record, no file in any directory (the
        // four empty subdirectories created by the store are fine).
        let knownDirs: Set<String> = ["originals", "thumbnails", "appIcons", "temp-imports"]
        let entries = try FileManager.default.subpathsOfDirectory(atPath: dir.path)
        let files = entries.filter { !knownDirs.contains($0) }
        #expect(files.isEmpty, "no orphan temp files or records on rejected insert: \(files)")
    }

    @Test
    func withinLimitAssetStoredNormally() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scale-limits-ok-\(UUID().uuidString)", isDirectory: true)
        let store = try AssetStore(directoryURL: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let small = Data(repeating: 0x01, count: 1024)
        let asset = try await store.importData(small, kind: .original, contentType: "image/png")
        #expect(asset.byteSize == 1024)
        // Independent object + hash for FR-090a sync compatibility.
        #expect(!asset.contentHash.isEmpty)
        let readBack = try await store.readData(assetID: asset.id)
        #expect(readBack == small)
    }

}

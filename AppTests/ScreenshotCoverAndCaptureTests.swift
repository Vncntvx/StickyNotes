import Testing
import Foundation
import Domain
import Persistence
import AssetStore
@testable import StickyNotes

// MARK: - Screenshot cover + capture pipeline tests (T292/T293, US7)
//
// Per tasks.md T292/T293: cover selection persists transactionally
// (FR-094/FR-094b), captions persist (FR-093), the capture pipeline stores
// assets and inserts a screenshot block (FR-091/FR-090a), and the embedded
// image actions resolve through the AssetStore (FR-090).

@MainActor
@Suite struct ScreenshotCoverAndCaptureTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000012")!

    /// A 1×1 PNG (deterministic fixture; no real capture needed).
    nonisolated private static let pngFixture = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!

    private func makeEnvironment() throws -> (AppEnvironment, URL) {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let assetRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("assets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: assetRoot, withIntermediateDirectories: true)
        let assetStore = try AssetStore(directoryURL: assetRoot)
        let env = AppEnvironment(
            persistence: PersistenceServices(store: store),
            assets: AssetServices(directoryURL: assetRoot, store: assetStore),
        )
        return (env, assetRoot)
    }

    private func insertScreenshotBlock(env: AppEnvironment, noteId: UUID, assetID: UUID) async throws -> UUID {
        let blockId = UUID()
        let block = Block(
            id: blockId,
            noteId: noteId,
            kind: .screenshot,
            sortKey: 0,
            payload: .screenshot(ScreenshotPayload(
                originalAssetId: assetID,
                thumbnailAssetId: assetID,
                caption: nil,
                capturedAt: Date(),
                isCover: false
            )),
            lastModifiedDeviceId: Self.deviceId
        )
        try await env.persistence.noteRepository!.insert(block)
        return blockId
    }

    /// A fresh host whose in-memory block list includes the inserted block.
    private func freshHost(env: AppEnvironment, noteId: UUID) async -> NoteWindowHostModel {
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        return host
    }

    @Test
    func coverSelectionPersistsAndSurvivesRelaunch() async throws {
        let (env, _) = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let initialHost = NoteWindowHostModel(noteId: noteId, environment: env)
        await initialHost.load()
        let blockId = try await insertScreenshotBlock(env: env, noteId: noteId, assetID: UUID())
        let host = await freshHost(env: env, noteId: noteId)

        // FR-094: set the cover (at most one per note).
        await host.setCover(blockId: blockId, isCover: true)
        try await Task.sleep(for: .milliseconds(300))

        let reloaded = NoteWindowHostModel(noteId: noteId, environment: env)
        await reloaded.load()
        #expect(reloaded.note?.coverScreenshotBlockId == blockId, "cover persists (FR-094)")

        // FR-094b: deleting the cover block nullifies the reference.
        await reloaded.deleteBlock(id: blockId)
        try await Task.sleep(for: .milliseconds(300))
        let after = NoteWindowHostModel(noteId: noteId, environment: env)
        await after.load()
        #expect(after.note?.coverScreenshotBlockId == nil, "no dangling cover reference (FR-094b)")
    }

    @Test
    func captionPersists() async throws {
        let (env, _) = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let initialHost = NoteWindowHostModel(noteId: noteId, environment: env)
        await initialHost.load()
        let blockId = try await insertScreenshotBlock(env: env, noteId: noteId, assetID: UUID())
        let host = await freshHost(env: env, noteId: noteId)

        await host.updateCaption(blockId: blockId, caption: "my capture")
        try await Task.sleep(for: .milliseconds(300))
        let blocks = try await env.persistence.noteRepository!.fetchBlocks(noteId: noteId)
        if case .screenshot(let payload) = blocks.first(where: { $0.id == blockId })?.payload {
            #expect(payload.caption == "my capture", "caption persists (FR-093)")
        } else {
            Issue.record("expected screenshot payload")
        }
    }

    @Test
    func capturePipelineStoresAssetAndInsertsBlock() async throws {
        let (env, assetRoot) = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()

        // FR-091: capture with an injected data provider (no real screen).
        let captured = await host.captureRegion(dataProvider: { Self.pngFixture })
        #expect(captured, "capture succeeded")

        let blocks = try await env.persistence.noteRepository!.fetchBlocks(noteId: noteId)
        guard let screenshot = blocks.first(where: { $0.kind == .screenshot }) else {
            Issue.record("no screenshot block inserted")
            return
        }
        if case .screenshot(let payload) = screenshot.payload {
            // FR-090a: original + 256px thumbnail stored as assets.
            let assetStore = env.assets.store!
            let original = try await assetStore.readData(assetID: payload.originalAssetId)
            #expect(original == Self.pngFixture, "original asset bytes stored (FR-090a)")
            guard let thumbID = payload.thumbnailAssetId else {
                Issue.record("thumbnail must exist for a valid PNG fixture")
                return
            }
            let thumb = try await assetStore.readData(assetID: thumbID)
            #expect(!thumb.isEmpty, "thumbnail stored")
        } else {
            Issue.record("expected screenshot payload")
        }
        // Asset files live under the composed root (T293).
        let files = try FileManager.default.contentsOfDirectory(atPath: assetRoot.path)
        #expect(!files.isEmpty, "assets written to the sandbox asset root (T293)")
    }

    @Test
    func embeddedImageCopyAndRemoveResolveThroughAssetStore() async throws {
        let (env, _) = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let initialHost = NoteWindowHostModel(noteId: noteId, environment: env)
        await initialHost.load()

        // Import an embedded image via the asset store, then reference it.
        let assetStore = env.assets.store!
        let imported = try await assetStore.importData(Self.pngFixture, kind: .original, contentType: "public.png")
        let blockId = UUID()
        try await env.persistence.noteRepository!.insert(Block(
            id: blockId,
            noteId: noteId,
            kind: .image,
            sortKey: 0,
            payload: .image(EmbeddedImagePayload(originalAssetId: imported.id, thumbnailAssetId: imported.id)),
            lastModifiedDeviceId: Self.deviceId
        ))
        let host = await freshHost(env: env, noteId: noteId)

        let data = await host.embeddedImageData(blockId: blockId)
        #expect(data == Self.pngFixture, "embedded image bytes resolvable (FR-090)")

        await host.performEmbeddedImageAction(blockId: blockId, action: .remove)
        let blocks = try await env.persistence.noteRepository!.fetchBlocks(noteId: noteId)
        #expect(!blocks.contains { $0.id == blockId }, "remove deletes the image block (FR-090)")
    }

    // MARK: - R1.3 capture failure fail-closed (remediation-phase1 T012/T013)
    //
    // The capture pipeline must NEVER produce a note mutation from failed
    // or empty capture data (Core T303 fail-closed contract), and a
    // missing thumbnail must never fall back to the full-resolution
    // original (SC-008: the card grid never decodes an original).

    @Test
    func captureProviderFailureLeavesNoSideEffects() async throws {
        // T012: a throwing capture provider → capture fails, no block, no
        // asset. (Guard test: locks in the existing fail-closed behavior.)
        let (env, _) = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = await freshHost(env: env, noteId: noteId)
        let blockCountBefore = host.blocks.count
        let assetsBefore = await env.assets.store?.snapshot().count ?? 0

        let ok = await host.captureRegion(
            dataProvider: { throw StickyError.capture(.captureStreamFailed) },
            target: .append
        )
        #expect(ok == false, "capture failure must report failure")
        #expect(host.blocks.count == blockCountBefore, "no block inserted on capture failure")
        #expect((await env.assets.store?.snapshot().count ?? 0) == assetsBefore,
                "no asset stored on capture failure")
    }

    @Test
    func emptyCaptureDataIsRejected() async throws {
        // T013a: empty data (the pre-fix CaptureFlow swallowed errors into
        // `Data()` and the empty PNG was stored as a successful screenshot)
        // must be rejected — no block, no asset, failure reported.
        let (env, _) = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = await freshHost(env: env, noteId: noteId)
        let blockCountBefore = host.blocks.count
        let assetsBefore = await env.assets.store?.snapshot().count ?? 0

        let ok = await host.captureRegion(dataProvider: { Data() }, target: .append)
        #expect(ok == false, "empty capture data must be rejected, never stored as a screenshot")
        #expect(host.blocks.count == blockCountBefore, "no block inserted for empty data")
        #expect((await env.assets.store?.snapshot().count ?? 0) == assetsBefore,
                "no asset stored for empty data")
    }

    @Test
    func thumbnailFailureDoesNotFallBackToOriginal() async throws {
        // T013b (SC-008): when thumbnail generation fails, the block's
        // thumbnailAssetId must be nil — never the original asset id (the
        // card grid would decode a full-resolution original).
        // Deterministic injection: non-image bytes pass the size check,
        // store as an original, and fail thumbnail generation.
        let (env, _) = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = await freshHost(env: env, noteId: noteId)
        let blockCountBefore = host.blocks.count

        let ok = await host.captureRegion(
            dataProvider: { Data("garbage-bytes-that-are-not-an-image".utf8) },
            target: .append
        )
        #expect(ok == true, "the original bytes still store (thumbnail failure is not a capture failure)")
        #expect(host.blocks.count == blockCountBefore + 1, "a screenshot block is inserted")
        guard let block = host.blocks.last, case .screenshot(let payload) = block.payload else {
            Issue.record("expected a screenshot block")
            return
        }
        #expect(payload.thumbnailAssetId == nil,
                "thumbnailAssetId must not fall back to the original (SC-008)")
    }
}

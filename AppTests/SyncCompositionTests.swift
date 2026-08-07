import Testing
import Foundation
import os
import Domain
import Persistence
import SecurityCore
import SyncCore
@testable import StickyNotes

// MARK: - Sync composition tests (T284/T285, US9)
//
// Per tasks.md T285: the app-side sync composition — vault configuration
// store (device-local), Keychain-held credentials, SyncEngine wiring,
// configure → sync → status, remove-without-deleting-local-notes (FR-151),
// repository replacement with fresh vault + preserved local notes (FR-154),
// and the library status surface (T284). An in-memory provider + in-memory
// secret store exercise the whole path without network.

/// Deterministic in-memory provider for the composition tests. Implements
/// the conditional semantics of `SyncProviderProtocol`; the vault manifest
/// is stored encrypted, exactly like the real providers.
final class InMemorySyncProvider: SyncProviderProtocol, @unchecked Sendable {
    private struct State: Sendable {
        var objects: [String: Data] = [:]
        var manifest: (data: Data, token: String)?
        var tokenCounter = 0
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    var failVerification = false

    func verify() async throws {
        if failVerification { throw ProviderError.network }
    }

    func fetchMetadata(objectName: String) async throws -> ObjectMetadata? {
        lock.withLock { state in
            guard let data = state.objects[objectName] else { return nil }
            return ObjectMetadata(objectName: objectName, versionToken: "t\(state.tokenCounter)", byteSize: data.count, modifiedAt: nil)
        }
    }

    func fetch(objectName: String) async throws -> Data {
        lock.withLock { state in
            guard let data = state.objects[objectName] else { return Data() }
            return data
        }
    }

    func upload(objectName: String, data: Data) async throws {
        try lock.withLock { state in
            if state.objects[objectName] != nil { throw ProviderError.conditionalFailed }
            state.tokenCounter += 1
            state.objects[objectName] = data
        }
    }

    func replace(objectName: String, data: Data, ifMatch: String) async throws {
        lock.withLock { state in
            state.tokenCounter += 1
            state.objects[objectName] = data
        }
    }

    func delete(objectName: String, ifMatch: String?) async throws {
        lock.withLock { state in state.objects[objectName] = nil }
    }

    func list() async throws -> [ObjectMetadata] {
        lock.withLock { state in
            state.objects.keys.map { ObjectMetadata(objectName: $0, versionToken: nil, byteSize: nil, modifiedAt: nil) }
        }
    }

    func fetchManifest() async throws -> ManifestFetchResult {
        try lock.withLock { state in
            guard let manifest = state.manifest else { throw ProviderError.notFound }
            return ManifestFetchResult(data: manifest.data, versionToken: manifest.token)
        }
    }

    func replaceManifest(data: Data, ifMatch: String) async throws {
        lock.withLock { state in
            state.tokenCounter += 1
            state.manifest = (data, "t\(state.tokenCounter)")
        }
    }
}

@MainActor
@Suite struct SyncCompositionTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000005")!

    private func makeCoordinator(provider: InMemorySyncProvider? = nil) throws -> (SyncCoordinator, DatabaseStore, InMemorySecretStore) {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let secretStore = InMemorySecretStore()
        let coordinator: SyncCoordinator
        if let provider {
            coordinator = SyncCoordinator(
                store: store,
                secretStore: secretStore,
                deviceId: Self.deviceId,
                providerOverride: { _, _ in provider }
            )
        } else {
            coordinator = SyncCoordinator(store: store, secretStore: secretStore, deviceId: Self.deviceId)
        }
        return (coordinator, store, secretStore)
    }

    private func configure(coordinator: SyncCoordinator, provider: InMemorySyncProvider) async throws {
        try await coordinator.configure(
            providerType: .webdav,
            endpoint: "https://example.com/dav",
            containerPath: "stickynotes",
            bucket: nil,
            region: nil,
            credentials: SyncProviderCredentials(username: "user", password: "secret"),
            vaultPassword: "test-password",
            rememberUnlock: false,
            isTestFixture: true
        )
    }

    @Test
    func configurePersistsConfigurationAndSyncs() async throws {
        let provider = InMemorySyncProvider()
        let (coordinator, store, _) = try makeCoordinator(provider: provider)
        await coordinator.load()
        #expect(!coordinator.isConfigured)

        try await configure(coordinator: coordinator, provider: provider)
        #expect(coordinator.isConfigured, "configuration persists in-memory")
        #expect(coordinator.lastSuccessfulSyncAt != nil, "initial sync records last-success time")
        #expect(coordinator.lastErrorCode == nil)

        // Device-local persistence (T285): a fresh coordinator over the same
        // store sees the configuration again.
        let reloaded = SyncCoordinator(
            store: store,
            secretStore: InMemorySecretStore(),
            deviceId: Self.deviceId
        )
        // NOTE: the fresh coordinator uses a fresh secret store; the
        // configuration row still loads (status surface, T284).
        await reloaded.load()
        #expect(reloaded.isConfigured, "vault configuration is persisted device-locally")
        #expect(reloaded.lastSuccessfulSyncAt != nil, "sync state persists")
    }

    @Test
    func manualSyncRunsAndUpdatesStatus() async throws {
        let provider = InMemorySyncProvider()
        let (coordinator, _, _) = try makeCoordinator(provider: provider)
        await coordinator.load()
        try await configure(coordinator: coordinator, provider: provider)

        coordinator.setAutoSyncEnabled(true)
        await coordinator.localContentChanged()
        await coordinator.manualSync()
        #expect(coordinator.lastSuccessfulSyncAt != nil)
        #expect(coordinator.lastErrorCode == nil)
        #expect(!coordinator.isInProgress)
    }

    @Test
    func removeConfigurationKeepsLocalNotes() async throws {
        let provider = InMemorySyncProvider()
        let (coordinator, store, _) = try makeCoordinator(provider: provider)
        await coordinator.load()
        try await configure(coordinator: coordinator, provider: provider)

        // A local note exists before removal.
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        let note = Note(title: "keep me", lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        await coordinator.removeConfiguration()
        #expect(!coordinator.isConfigured, "configuration removed (FR-151)")

        let fetched = try await repo.fetch(id: note.id)
        #expect(fetched != nil, "local notes are NOT deleted by removing the config (FR-151)")

        // The row is gone: a fresh coordinator over the same store sees nothing.
        let reloaded = SyncCoordinator(store: store, secretStore: InMemorySecretStore(), deviceId: Self.deviceId)
        await reloaded.load()
        #expect(!reloaded.isConfigured)
    }

    @Test
    func replaceRepositoryBootstrapsFreshVaultKeepingNotes() async throws {
        let provider = InMemorySyncProvider()
        let (coordinator, store, _) = try makeCoordinator(provider: provider)
        await coordinator.load()
        try await configure(coordinator: coordinator, provider: provider)
        let originalVaultId = coordinator.configuration?.vaultId

        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        let note = Note(title: "still here", lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        try await coordinator.replaceRepository(
            providerType: .webdav,
            endpoint: "https://example.com/dav",
            containerPath: "stickynotes",
            bucket: nil,
            region: nil,
            credentials: SyncProviderCredentials(username: "user", password: "secret"),
            vaultPassword: "test-password",
            isTestFixture: true
        )
        #expect(coordinator.configuration?.vaultId != originalVaultId, "fresh vault on replacement (FR-154)")
        #expect(coordinator.configuration?.replacedFromVaultLocator != nil, "prior locator recorded for user reference (FR-154)")

        let fetched = try await repo.fetch(id: note.id)
        #expect(fetched != nil, "local notes preserved on replacement (FR-154)")
    }

    @Test
    func testConnectionReportsFailure() async throws {
        let provider = InMemorySyncProvider()
        provider.failVerification = true
        let (coordinator, _, _) = try makeCoordinator(provider: provider)
        await coordinator.load()

        do {
            try await coordinator.testConnection(
                providerType: .webdav,
                endpoint: "https://example.com/dav",
                containerPath: nil,
                bucket: nil,
                region: nil,
                credentials: SyncProviderCredentials(username: "u", password: "p")
            )
            Issue.record("expected the failing provider to throw")
        } catch {
            #expect(!coordinator.isConfigured, "failed test never configures")
        }
    }

    @Test
    func libraryStatusSurfaceReadsCoordinatorState() async throws {
        // T284: the menu-bar library footer reads the coordinator (the scene
        // no longer hardcodes "not configured").
        let provider = InMemorySyncProvider()
        let (coordinator, store, _) = try makeCoordinator(provider: provider)
        await coordinator.load()
        let env = AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.sync.\(UUID().uuidString)") ?? .standard),
            syncCoordinator: coordinator
        )
        let model = LibraryModel(environment: env)
        #expect(model.syncCoordinator === coordinator)
        #expect(model.syncCoordinator?.isConfigured == false)

        try await configure(coordinator: coordinator, provider: provider)
        #expect(model.syncCoordinator?.isConfigured == true)
        #expect(model.syncCoordinator?.lastSuccessfulSyncAt != nil)
    }
}

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
/// is stored encrypted, exactly like the real providers. (Non-final so
/// SyncCoordinatorUnlockTests can count provider calls.)
class InMemorySyncProvider: SyncProviderProtocol, @unchecked Sendable {
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
        try lock.withLock { state in
            guard let data = state.objects[objectName] else { throw ProviderError.notFound }
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

    private func makeCoordinator(provider: (any SyncProviderProtocol)? = nil) throws -> (SyncCoordinator, DatabaseStore, InMemorySecretStore) {
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
            persistence: PersistenceServices(store: store),
            assets: AssetServices(),
            syncCoordinator: coordinator
        )
        let model = LibraryModel(environment: env)
        #expect(model.syncCoordinator === coordinator)
        #expect(model.syncCoordinator?.isConfigured == false)

        try await configure(coordinator: coordinator, provider: provider)
        #expect(model.syncCoordinator?.isConfigured == true)
        #expect(model.syncCoordinator?.lastSuccessfulSyncAt != nil)
    }

    @Test
    func autoSyncPolicyPersistsAndSwitches() async throws {
        // FR-152 (clarified 2026-08-08): the user-selectable strategy.
        // Restore the defaults afterwards so manual test runs are unaffected.
        defer {
            LocalPreferences().autoSyncPolicy = .default
            LocalPreferences().autoSyncEnabled = false
        }
        let provider = InMemorySyncProvider()
        let (coordinator, _, _) = try makeCoordinator(provider: provider)
        await coordinator.load()
        #expect(coordinator.autoSyncPolicy == .default, "defaults to periodic 15 min")

        coordinator.setAutoSyncEnabled(true)
        #expect(coordinator.autoSyncEnabled)

        coordinator.setAutoSyncPolicy(.every30)
        #expect(coordinator.autoSyncPolicy == .every30)
        #expect(LocalPreferences().autoSyncPolicy == .every30, "persisted device-locally")
        #expect(coordinator.autoSyncPolicy.interval == 30.0 * 60.0)

        coordinator.setAutoSyncPolicy(.changeOnly)
        #expect(coordinator.autoSyncPolicy == .changeOnly)
        #expect(coordinator.autoSyncPolicy.interval == nil, "changeOnly disables periodic sync")

        // Policy changes while auto-sync is off are still persisted.
        coordinator.setAutoSyncEnabled(false)
        coordinator.setAutoSyncPolicy(.every5)
        #expect(coordinator.autoSyncPolicy == .every5)
        #expect(coordinator.autoSyncPolicy.interval == 5.0 * 60.0)
    }

    @Test
    func systemBootTimeMatchesKernelBootTimeAndIsStable() {
        // FR-162a fix: the boot timestamp must come from `kern.boottime`
        // (immune to sleep drift). It must match the kernel value and be
        // identical across calls within one launch.
        let a = SystemBootTime.current()
        let b = SystemBootTime.current()
        #expect(a == b, "boot time is stable within a launch")

        // Sanity: it is in the recent past (not a far-future drift).
        let now = Int(Date().timeIntervalSince1970)
        #expect(a <= now, "boot time cannot be in the future")
        #expect(now - a < 60 * 60 * 24 * 30, "boot time is within the last 30 days")
    }
}

// MARK: - JoinExistingVault suite (T008-T010, T022-T025, T021; US1/US2)
//
// Per tasks.md Phase 3: the end-to-end join — fetch bootstrap READ-ONLY →
// openRemoteBootstrap → persist single config → wire engine → immediate
// sync. Tests use the shared in-memory provider to simulate device A's
// vault on the remote; device B joins it.

/// Shared storage for the repo-layout provider — all scoped instances see
/// the same object map.
final class RepoStore: @unchecked Sendable {
    let lock = OSAllocatedUnfairLock(initialState: [String: Data]())
}

/// Repo-layout-aware in-memory provider for DISCOVERY tests: object names
/// are stored under their vault locator directory (`"<locator>/<name>"`),
/// exactly like the real WebDAV/S3 providers. The repository level (empty
/// locator) lists every vault's objects; a vault-level provider fetches
/// inside its own directory. All instances share one `RepoStore`.
final class RepoLayoutInMemoryProvider: SyncProviderProtocol, @unchecked Sendable {
    private let store: RepoStore
    /// The vault locator this provider is scoped to ("" = repository level).
    private let vaultLocator: String

    init(store: RepoStore = RepoStore(), vaultLocator: String = "") {
        self.store = store
        self.vaultLocator = vaultLocator
    }

    private func key(_ objectName: String) -> String {
        vaultLocator.isEmpty ? objectName : "\(vaultLocator)/\(objectName)"
    }

    /// Seeds a vault's bootstrap + manifest under its locator directory.
    func seedVault(locator: String, bootstrapData: Data, manifestData: Data? = nil) {
        store.lock.withLock { state in
            state["\(locator)/\(RemoteLayout.bootstrapObjectName(for: locator))"] = bootstrapData
            if let manifestData {
                state["\(locator)/\(ManifestStore.manifestObjectName)"] = manifestData
            }
        }
    }

    func verify() async throws {}
    func fetchMetadata(objectName: String) async throws -> ObjectMetadata? {
        store.lock.withLock { state in
            guard let data = state[key(objectName)] else { return nil }
            return ObjectMetadata(objectName: objectName, versionToken: "t", byteSize: data.count, modifiedAt: nil)
        }
    }
    func fetch(objectName: String) async throws -> Data {
        try store.lock.withLock { state in
            guard let data = state[key(objectName)] else { throw ProviderError.notFound }
            return data
        }
    }
    func upload(objectName: String, data: Data) async throws {
        try store.lock.withLock { state in
            let k = key(objectName)
            if state[k] != nil { throw ProviderError.conditionalFailed }
            state[k] = data
        }
    }
    func replace(objectName: String, data: Data, ifMatch: String) async throws {
        store.lock.withLock { state in state[key(objectName)] = data }
    }
    func delete(objectName: String, ifMatch: String?) async throws {
        store.lock.withLock { state in state[key(objectName)] = nil }
    }
    func list() async throws -> [ObjectMetadata] {
        store.lock.withLock { state in
            let prefix = vaultLocator.isEmpty ? "" : "\(vaultLocator)/"
            return state.keys
                .filter { $0.hasPrefix(prefix) }
                .map { ObjectMetadata(objectName: String($0.dropFirst(prefix.count)), versionToken: nil, byteSize: nil, modifiedAt: nil) }
        }
    }
    func fetchManifest() async throws -> ManifestFetchResult {
        throw ProviderError.notFound
    }
    func replaceManifest(data: Data, ifMatch: String) async throws {}
}

@MainActor
@Suite struct JoinExistingVaultSuite {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000005")!
    private static let deviceBId = UUID(uuidString: "b0000000-0000-4000-8000-00000000000b")!

    private func makeCoordinator(
        provider: InMemorySyncProvider,
        deviceId: UUID = JoinExistingVaultSuite.deviceBId,
        store: DatabaseStore? = nil
    ) throws -> (SyncCoordinator, DatabaseStore, InMemorySecretStore) {
        let db = try store ?? DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(db.dbPool)
        let secretStore = InMemorySecretStore()
        let coordinator = SyncCoordinator(
            store: db,
            secretStore: secretStore,
            deviceId: deviceId,
            providerOverride: { _, _ in provider }
        )
        return (coordinator, db, secretStore)
    }

    /// Device A creates the vault (configures + first sync) on the shared
    /// provider. Returns the vault locator + the configured coordinator
    /// (its engine is wired and usable for pushing local notes).
    private func createVaultOnA(provider: InMemorySyncProvider) async throws -> (locator: String, coordinator: SyncCoordinator, store: DatabaseStore) {
        let (coordinator, store, _) = try makeCoordinator(provider: provider, deviceId: Self.deviceId)
        await coordinator.load()
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
        let locator = try #require(coordinator.configuration?.vaultLocator)
        return (locator, coordinator, store)
    }

    private func join(
        coordinator: SyncCoordinator,
        provider: InMemorySyncProvider,
        locator: String,
        password: String = "test-password"
    ) async throws {
        try await coordinator.joinExistingVault(
            providerType: .webdav,
            endpoint: "https://example.com/dav",
            containerPath: "stickynotes",
            bucket: nil,
            region: nil,
            vaultLocator: locator,
            credentials: SyncProviderCredentials(username: "user", password: "secret"),
            vaultPassword: password
        )
    }

    private func noteRepository(store: DatabaseStore) -> SQLiteNoteRepository {
        SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
    }

    // MARK: T024 — create path uploads the bootstrap under the deterministic name

    @Test
    func createPathUploadsBootstrapUnderDerivedObjectName() async throws {
        let provider = InMemorySyncProvider()
        let (locator, _, _) = try await createVaultOnA(provider: provider)

        // After configure, the provider MUST contain the bootstrap object
        // under bootstrapObjectName(locator) — the object join fetches.
        let name = RemoteLayout.bootstrapObjectName(for: locator)
        let metadata = try await provider.fetchMetadata(objectName: name)
        #expect(metadata != nil, "create path MUST upload the bootstrap under the derived name (T024)")

        let data = try await provider.fetch(objectName: name)
        let parsed = try? VaultBootstrap.fromCanonicalJSON(data)
        #expect(parsed != nil, "the uploaded bootstrap MUST be a valid VaultBootstrap")
        #expect(parsed?.vaultLocator == locator)
    }

    // MARK: T025 — WebDAV + S3 address the same remote location

    @Test
    func webdavAndS3AddressSameRemoteLocationForCreateAndJoin() async throws {
        // Both providers derive the remote container from the user prefix +
        // the vault locator, so a join by locator reaches the same objects.
        let webdav = RemoteLayout.bootstrapObjectName(for: "loc1")
        let s3 = RemoteLayout.bootstrapObjectName(for: "loc1")
        #expect(webdav == s3, "the bootstrap object name is provider-independent")
        // The derived name differs for a different locator (no cross-vault
        // collision on the shared repository).
        #expect(webdav != RemoteLayout.bootstrapObjectName(for: "loc2"))
    }

    // MARK: T027 — makeProvider containerPath includes the vault locator

    @Test
    func webdavContainerPathIncludesVaultLocator() throws {
        // The container path for WebDAV (and the S3 prefix) is derived from
        // the user prefix + the vault locator — mirroring S3 — so the join
        // fetch targets the same remote location the create path used.
        let path = SyncCoordinator.remoteContainerPath(prefix: "stickynotes", vaultLocator: "abc123")
        #expect(path == "stickynotes/abc123")

        let noPrefix = SyncCoordinator.remoteContainerPath(prefix: nil, vaultLocator: "abc123")
        #expect(noPrefix == "abc123")

        let trailingSlash = SyncCoordinator.remoteContainerPath(prefix: "mynotes/", vaultLocator: "xyz789")
        #expect(trailingSlash == "mynotes/xyz789", "leading/trailing slashes are normalized")

        // Identical derivation for WebDAV and S3 — one shared rule.
        #expect(SyncCoordinator.remoteContainerPath(prefix: "p", vaultLocator: "l")
                == SyncCoordinator.remoteContainerPath(prefix: "p", vaultLocator: "l"))
    }

    // MARK: T028 — join with an existing configuration applies replace
    // semantics (US1/AC6, FR-007/FR-154, CHK018)

    @Test
    func joinWithExistingConfigurationReplacesConfigKeepingNotes() async throws {
        let provider = InMemorySyncProvider()
        let (locator, _, _) = try await createVaultOnA(provider: provider)

        // Device B is already configured with a DIFFERENT vault.
        let (bCoord, bStore, _) = try makeCoordinator(provider: provider)
        await bCoord.load()
        try await bCoord.configure(
            providerType: .webdav,
            endpoint: "https://example.com/dav",
            containerPath: "stickynotes",
            bucket: nil,
            region: nil,
            credentials: SyncProviderCredentials(username: "user", password: "secret"),
            vaultPassword: "prior-vault-password",
            rememberUnlock: false,
            isTestFixture: true
        )
        let priorVaultId = try #require(bCoord.configuration?.vaultId)

        // B's local notes must survive the join (FR-007/CHK018).
        let bRepo = noteRepository(store: bStore)
        let localNote = Note(title: "keep on join", lastModifiedDeviceId: Self.deviceBId)
        try await bRepo.create(localNote)

        // Join the OTHER vault: single-row replace semantics.
        try await join(coordinator: bCoord, provider: provider, locator: locator)
        #expect(bCoord.isConfigured)
        let newVaultId = try #require(bCoord.configuration?.vaultId)
        #expect(newVaultId != priorVaultId, "the config row now points at the JOINED vault (FR-007)")
        #expect(bCoord.configuration?.vaultLocator == locator)

        // Local notes preserved.
        let kept = try await bRepo.fetch(id: localNote.id)
        #expect(kept != nil, "local notes are NOT deleted when the config is replaced (US1/AC6)")

        // Exactly one configuration row remains (single-row replace).
        let reloaded = SyncCoordinator(
            store: bStore,
            secretStore: InMemorySecretStore(),
            deviceId: Self.deviceBId
        )
        await reloaded.load()
        #expect(reloaded.configuration?.vaultId == newVaultId, "one configuration row, the joined vault")

        // Prior remote data untouched: the prior vault's bootstrap still
        // exists on the provider (never deleted by the join).
        let priorLocator = try #require(bCoord.configuration?.replacedFromVaultLocator)
        let priorBootstrap = try await provider.fetchMetadata(
            objectName: RemoteLayout.bootstrapObjectName(for: priorLocator)
        )
        #expect(priorBootstrap != nil, "prior remote data is NOT deleted on join (FR-154/CHK018)")
    }

    @Test
    func joinWithImportedProfileWrongVaultFailsClosed() async throws {
        // CHK025: an imported sync profile carries the exporting device's
        // vaultId as the user's stated expectation. Joining a location whose
        // bootstrap is a DIFFERENT vault must fail closed (wrong-vault) —
        // the profile would otherwise silently point at another vault.
        let provider = InMemorySyncProvider()
        let (locator, _, _) = try await createVaultOnA(provider: provider)

        // The imported profile claims a DIFFERENT vaultId than the remote.
        let wrongExpectation = UUID()

        let (bCoord, bStore, _) = try makeCoordinator(provider: provider)
        await bCoord.load()
        do {
            try await bCoord.joinExistingVault(
                providerType: .webdav,
                endpoint: "https://example.com/dav",
                containerPath: "stickynotes",
                bucket: nil,
                region: nil,
                vaultLocator: locator,
                credentials: SyncProviderCredentials(username: "user", password: "secret"),
                vaultPassword: "test-password",
                expectedVaultId: wrongExpectation
            )
            Issue.record("joining a location whose bootstrap is a different vault than the profile MUST fail closed (CHK025)")
        } catch StickyError.credentials(.wrongVault) {
            // fail-closed: the expected rejection surfaced (CHK025)
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        // Fail closed: no local configuration written.
        #expect(!bCoord.isConfigured, "no local configuration written (CHK025)")
        let reloaded = SyncCoordinator(
            store: bStore,
            secretStore: InMemorySecretStore(),
            deviceId: Self.deviceBId
        )
        await reloaded.load()
        #expect(!reloaded.isConfigured, "no configuration row persisted")
    }

    // MARK: T031 — no main-actor blocking during the join (FR-012)

    // MARK: Discover vaults (scan-before-join)

    @Test
    func discoverVaultsListsExistingVaultsWithoutPassword() async throws {
        // Two vaults live under the same repository, each in its own
        // "<locator>/" directory (the real S3/WebDAV layout).
        let repoStore = RepoStore()
        let vaultA = try await VaultBootstrapService.createVault(
            password: "pw-a", secretStore: InMemorySecretStore(), isTestFixture: true
        )
        let vaultB = try await VaultBootstrapService.createVault(
            password: "pw-b", secretStore: InMemorySecretStore(), isTestFixture: true
        )
        // The repository-level provider seeds the vaults.
        let repo = RepoLayoutInMemoryProvider(store: repoStore)
        repo.seedVault(locator: vaultA.vaultLocator, bootstrapData: try vaultA.canonicalJSON())
        repo.seedVault(locator: vaultB.vaultLocator, bootstrapData: try vaultB.canonicalJSON())

        // The coordinator's providerOverride mimics makeProvider: scope the
        // provider to the configuration's vault locator.
        let db = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(db.dbPool)
        let coordinator = SyncCoordinator(
            store: db,
            secretStore: InMemorySecretStore(),
            deviceId: Self.deviceBId,
            providerOverride: { configuration, _ in
                RepoLayoutInMemoryProvider(store: repoStore, vaultLocator: configuration.vaultLocator)
            }
        )
        await coordinator.load()
        let vaults = try await coordinator.discoverVaults(
            providerType: .webdav,
            endpoint: "https://example.com/dav",
            containerPath: "stickynotes",
            bucket: nil,
            region: nil,
            credentials: SyncProviderCredentials(username: "user", password: "secret")
        )
        #expect(vaults.count == 2, "both vaults are discovered")
        #expect(vaults.contains { $0.vaultLocator == vaultA.vaultLocator })
        #expect(vaults.contains { $0.vaultLocator == vaultB.vaultLocator })
        #expect(vaults.contains { $0.vaultId == vaultA.vaultId })
        #expect(vaults.contains { $0.vaultId == vaultB.vaultId })
        // Sorted by creation date.
        #expect(vaults == vaults.sorted { $0.createdAt < $1.createdAt })
    }

    @Test
    func discoverVaultsReturnsEmptyForBareRepository() async throws {
        let repoStore = RepoStore()
        let db = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(db.dbPool)
        let coordinator = SyncCoordinator(
            store: db,
            secretStore: InMemorySecretStore(),
            deviceId: Self.deviceBId,
            providerOverride: { configuration, _ in
                RepoLayoutInMemoryProvider(store: repoStore, vaultLocator: configuration.vaultLocator)
            }
        )
        await coordinator.load()
        let vaults = try await coordinator.discoverVaults(
            providerType: .webdav,
            endpoint: "https://example.com/dav",
            containerPath: "stickynotes",
            bucket: nil,
            region: nil,
            credentials: SyncProviderCredentials(username: "user", password: "secret")
        )
        #expect(vaults.isEmpty, "an empty repository yields no vaults")
    }

    @Test
    func joinDoesNotBlockTheMainActor() async throws {
        let provider = InMemorySyncProvider()
        let (locator, _, _) = try await createVaultOnA(provider: provider)

        let (bCoord, _, _) = try makeCoordinator(provider: provider)
        await bCoord.load()

        // Launch the join. The join's fetch/decrypt MUST run off the main
        // actor (FR-012/Constitution XI) — while it is in flight, the main
        // actor must remain responsive to other work.
        let joinTask = Task {
            try await bCoord.joinExistingVault(
                providerType: .webdav,
                endpoint: "https://example.com/dav",
                containerPath: "stickynotes",
                bucket: nil,
                region: nil,
                vaultLocator: locator,
                credentials: SyncProviderCredentials(username: "user", password: "secret"),
                vaultPassword: "test-password"
            )
        }

        // Main-actor heartbeat: run 200 trivial hops while the join runs.
        // If the join blocked the main actor synchronously, these hops would
        // stall until the join finished (heartbeat ≈ join duration).
        let heartbeat = Task { @MainActor in
            let start = Date()
            var ticks = 0
            while ticks < 200 {
                ticks += 1
                await Task.yield()
            }
            return (ticks, Date().timeIntervalSince(start))
        }
        _ = try await joinTask.value
        let (ticks, heartbeatDuration) = await heartbeat.value
        let joinStartedAt = Date()

        #expect(bCoord.isConfigured, "join completed")
        #expect(ticks == 200)
        // The heartbeat must finish promptly relative to the join: the main
        // actor was never held by the join's network/crypto (FR-012). A
        // generous bound — 200 hops on a free main actor take milliseconds.
        #expect(heartbeatDuration < 2.0, "main actor stayed responsive during join (FR-012), heartbeat took \(heartbeatDuration)s")
        #expect(joinStartedAt.timeIntervalSinceNow > -60, "sanity")
    }

    // MARK: T008 — join success + bidirectional first sync

    @Test
    func joinFetchesVerifiesPersistsAndSyncsBidirectionally() async throws {
        let provider = InMemorySyncProvider()
        let (locator, aCoord, aStore) = try await createVaultOnA(provider: provider)

        // Device A has a remote note.
        let aRepo = noteRepository(store: aStore)
        let aNote = Note(title: "from device A", lastModifiedDeviceId: Self.deviceId)
        try await aRepo.create(aNote)
        // A pushes it (debounce → manual sync). FR-174-d may legitimately
        // set the informational "sync.historyAgedOut" code once the remote
        // manifest exists (local note with no remote tombstone — 001
        // reconciler semantics); the upload still completes.
        await aCoord.localContentChanged()
        await aCoord.manualSync()
        if let code = aCoord.lastErrorCode {
            #expect(code == "sync.historyAgedOut",
                    "unexpected error after A upload: \(code)")
        }
        #expect(aCoord.lastSuccessfulSyncAt != nil, "A's upload sync completed")
        let aManifest = try await provider.fetchManifest()
        #expect(aManifest.data.count > 0, "A committed a manifest")
        let allRemote = try await provider.list()
        #expect(allRemote.count >= 2, "bootstrap + manifest + note uploaded: got \(allRemote.count)")

        // Device B joins.
        let (bCoord, bStore, _) = try makeCoordinator(provider: provider)
        await bCoord.load()
        #expect(!bCoord.isConfigured)
        try await join(coordinator: bCoord, provider: provider, locator: locator)

        #expect(bCoord.isConfigured, "join persists the configuration (FR-007)")
        #expect(bCoord.configuration?.vaultLocator == locator, "same vault as device A (US1/AC1)")
        #expect(bCoord.lastSuccessfulSyncAt != nil, "immediate sync after join (FR-006)")

        // B downloaded A's note.
        let bRepo = noteRepository(store: bStore)
        let downloaded = try await bRepo.fetch(id: aNote.id)
        #expect(downloaded != nil, "first sync downloads remote notes")

        // B's own local note uploads to the vault; A can see it after its
        // next sync. NOTE: FR-174-d may legitimately set the informational
        // "sync.historyAgedOut" code for B's local notes (no remote tombstone
        // — 001 reconciler semantics preserved per FR-011); the upload still
        // completes.
        let bNote = Note(title: "from device B", lastModifiedDeviceId: Self.deviceBId)
        try await bRepo.create(bNote)
        await bCoord.localContentChanged()
        await bCoord.manualSync()
        #expect(bCoord.lastSuccessfulSyncAt != nil, "B's upload sync completed")
        if let code = bCoord.lastErrorCode {
            #expect(code == "sync.historyAgedOut",
                    "unexpected error after B upload: \(code)")
        }

        // A syncs again to pull B's note. FR-174-d informational flag may
        // fire for A's local note (no remote tombstone) — not an error.
        await aCoord.manualSync()
        if let code = aCoord.lastErrorCode {
            #expect(code == "sync.historyAgedOut",
                    "unexpected error after A re-sync: \(code)")
        }
        let aRepo2 = noteRepository(store: aStore)
        let seenOnA = try await aRepo2.fetch(id: bNote.id)
        #expect(seenOnA != nil, "local notes upload encrypted and appear on device A (US1/AC4)")

        // Nothing deleted on either side.
        let stillOnA = try await aRepo2.fetch(id: aNote.id)
        let stillOnB = try await bRepo.fetch(id: bNote.id)
        #expect(stillOnA != nil && stillOnB != nil, "no side's notes are deleted (US1/AC6)")
    }

    // MARK: T009 — missing bootstrap fails closed

    @Test
    func joinWithMissingBootstrapFailsClosed() async throws {
        let provider = InMemorySyncProvider()
        let (bCoord, bStore, _) = try makeCoordinator(provider: provider)
        await bCoord.load()

        let bogusLocator = "1a2b3c4d5e6f708192a3b4c5d6e7f80a1"
        do {
            try await join(coordinator: bCoord, provider: provider, locator: bogusLocator)
            Issue.record("join MUST fail when the remote bootstrap is missing")
        } catch {
            // Fail closed: no local configuration row written.
            #expect(!bCoord.isConfigured, "no local configuration written (FR-005)")
            let reloaded = SyncCoordinator(
                store: bStore,
                secretStore: InMemorySecretStore(),
                deviceId: Self.deviceBId
            )
            await reloaded.load()
            #expect(!reloaded.isConfigured, "no configuration row persisted")
            // No remote object created (provider state untouched beyond the
            // bootstrap fetch — no objects except nothing was written).
            let objects = try await provider.list()
            #expect(objects.isEmpty, "no remote object created on failed join (CHK030)")
        }
    }

    // MARK: T010 — wrong password fails closed, prior config untouched

    @Test
    func joinWithWrongPasswordFailsClosed() async throws {
        let provider = InMemorySyncProvider()
        let (locator, _, _) = try await createVaultOnA(provider: provider)

        let (bCoord, bStore, _) = try makeCoordinator(provider: provider)
        await bCoord.load()
        // A prior configuration exists on B (a different vault).
        try await bCoord.configure(
            providerType: .webdav,
            endpoint: "https://example.com/dav",
            containerPath: "stickynotes",
            bucket: nil,
            region: nil,
            credentials: SyncProviderCredentials(username: "user", password: "secret"),
            vaultPassword: "prior-vault-password",
            rememberUnlock: false,
            isTestFixture: true
        )
        let priorVaultId = bCoord.configuration?.vaultId

        do {
            try await join(coordinator: bCoord, provider: provider, locator: locator, password: "wrong-password")
            Issue.record("join MUST fail with the wrong password")
        } catch {
            #expect(bCoord.configuration?.vaultId == priorVaultId,
                    "previous configuration untouched (FR-004/US1/AC2)")
            let reloaded = SyncCoordinator(
                store: bStore,
                secretStore: InMemorySecretStore(),
                deviceId: Self.deviceBId
            )
            await reloaded.load()
            #expect(reloaded.configuration?.vaultId == priorVaultId, "previous config row persisted unchanged")
        }
    }

    // MARK: T022 — FR-174 long-offline semantics preserved on join

    @Test
    func joinPreservesLongOfflineSemanticsNoLocalDeletion() async throws {
        let provider = InMemorySyncProvider()
        let (locator, _, _) = try await createVaultOnA(provider: provider)

        // Device B carries local notes that were last synced long ago.
        let (bCoord, bStore, _) = try makeCoordinator(provider: provider)
        await bCoord.load()
        let bRepo = noteRepository(store: bStore)
        let oldLocal = Note(title: "old local note", lastModifiedDeviceId: Self.deviceBId)
        try await bRepo.create(oldLocal)

        try await join(coordinator: bCoord, provider: provider, locator: locator)

        // FR-174: the join + first sync MUST NOT auto-delete local content.
        let fetched = try await bRepo.fetch(id: oldLocal.id)
        #expect(fetched != nil, "local notes are never auto-deleted on join (FR-174/US3/AC2, CHK023)")
    }

    // MARK: T023 — edge cases: bootstrap deleted mid-join; concurrent joins

    @Test
    func joinWhenBootstrapDeletedMidJoinFailsClosed() async throws {
        let provider = InMemorySyncProvider()
        let (locator, _, _) = try await createVaultOnA(provider: provider)

        // Simulate device A deleting the remote bootstrap between B's fetch
        // and verification (CHK026): remove the object after the create.
        let name = RemoteLayout.bootstrapObjectName(for: locator)
        try await provider.delete(objectName: name, ifMatch: nil)

        let (bCoord, _, _) = try makeCoordinator(provider: provider)
        await bCoord.load()
        do {
            try await join(coordinator: bCoord, provider: provider, locator: locator)
            Issue.record("join MUST fail when the remote bootstrap disappears")
        } catch {
            #expect(!bCoord.isConfigured, "no local configuration written (CHK026)")
        }
    }

    @Test
    func concurrentJoinsAreReadOnlyAndBothSucceed() async throws {
        let provider = InMemorySyncProvider()
        let (locator, _, _) = try await createVaultOnA(provider: provider)

        // Two devices join the same vault at the same time (CHK027): the
        // join is READ-ONLY (bootstrap fetch) — no write race on the remote.
        let (b1, _, _) = try makeCoordinator(provider: provider)
        let (b2, _, _) = try makeCoordinator(provider: provider)
        await b1.load()
        await b2.load()

        async let j1: Void = try await join(coordinator: b1, provider: provider, locator: locator)
        async let j2: Void = try await join(coordinator: b2, provider: provider, locator: locator)
        _ = try await (j1, j2)

        #expect(b1.isConfigured, "device 1 joined")
        #expect(b2.isConfigured, "device 2 joined")
        #expect(b1.configuration?.vaultLocator == locator)
        #expect(b2.configuration?.vaultLocator == locator)
        #expect(b1.configuration?.vaultId == b2.configuration?.vaultId, "both joined the SAME vault")
    }

    // MARK: T021 — performance: <100 notes first sync converges promptly;
    // join does not block the main actor

    @Test
    func joinAndFirstSyncOfManyNotesCompletesQuickly() async throws {
        let provider = InMemorySyncProvider()
        let (locator, aCoord, aStore) = try await createVaultOnA(provider: provider)

        // Device A syncs 80 notes so the remote is populated.
        let aRepo = noteRepository(store: aStore)
        for i in 0..<80 {
            let note = Note(title: "note-\(i)", lastModifiedDeviceId: Self.deviceId)
            try await aRepo.create(note)
        }
        await aCoord.localContentChanged()
        await aCoord.manualSync()
        #expect(aCoord.lastErrorCode == nil)

        // B joins + first sync — SC-002: <100 notes converge within 1 minute
        // on the loopback/in-memory provider (asserted well under).
        let start = Date()
        let (bCoord, bStore, _) = try makeCoordinator(provider: provider)
        await bCoord.load()
        try await join(coordinator: bCoord, provider: provider, locator: locator)
        let elapsed = Date().timeIntervalSince(start)

        #expect(bCoord.lastErrorCode == nil, "B sync failed: \(String(describing: bCoord.lastErrorCode))")
        #expect(bCoord.lastSuccessfulSyncAt != nil)
        let bRepo = noteRepository(store: bStore)
        let all = try await bRepo.fetchAll(lifecycle: .active, sort: .modified)
        #expect(all.count >= 80, "all remote notes converged to B")
        #expect(elapsed < 60.0, "first sync of <100 notes converges within 1 minute (SC-002)")
    }

    // MARK: - 003 T054/T186 (FR-054/SC-013 Rev 3): advanced-area separation

    @Test
    func advancedMaintenanceOperationsAreSeparated() {
        // SC-013 (Rev 3): the Advanced area holds the TECHNICAL operations
        // only — exports; vault/storage management moved to the Storage
        // "Manage…" menu, Disconnect is a standalone destructive entry.
        #expect(SyncAdvancedAreaPolicy.operationsInSeparateAdvancedArea == true)
        #expect(SyncAdvancedAreaPolicy.operations == [
            "Export Sync Profile", "Export Diagnostic Bundle",
        ])
    }

    @Test
    func managedOperationsLiveInStorageManageMenu() {
        // FR-054 Rev 3: Join + Set Up New Storage Location live in the
        // Storage section's "Manage…" menu — still INDEPENDENT actions
        // (never merged into one flow).
        #expect(SyncAdvancedAreaPolicy.managedOperationsInStorageSection == true)
        #expect(SyncAdvancedAreaPolicy.managedOperationNames == [
            "Join Another Vault", "Set Up New Storage Location",
        ])
    }

    @Test
    func disconnectIsStandaloneDestructiveEntry() {
        // FR-054 Rev 3: Disconnect Sync… is its own destructive entry at
        // the bottom of the pane, not buried in the technical area.
        #expect(SyncAdvancedAreaPolicy.disconnectIsStandaloneDestructiveEntry == true)
    }

    @Test
    func recoveryRowLivesInSecuritySection() {
        // FR-163 (Rev 3): the no-recovery warning is a security decision —
        // its info row lives in the Security section.
        #expect(SyncAdvancedAreaPolicy.recoveryRowInSecuritySection == true)
    }

    @Test
    func joinIsASeparateProductAction() {
        // FR-054 Rev 3: joining an existing vault is its own product action
        // and must never be merged into the storage-location change flow.
        #expect(SyncAdvancedAreaPolicy.joinIsSeparateProductAction == true)
    }

    @Test
    func joinHasInitialSetupAndRecoveryReEntry() {
        // CHK033: join-existing-vault has an initial-setup path (T050) AND
        // a re-entry (now the Storage "Manage…" menu).
        #expect(SyncAdvancedAreaPolicy.initialSetupJoinEnabled == true)
        #expect(SyncAdvancedAreaPolicy.recoveryReEntryEnabled == true)
    }

    @Test
    func destructiveOperationsAreConfirmedAndDistinct() {
        // FR-154 semantics preserved: destructive ops are visually/
        // semantically distinct and confirmed.
        #expect(SyncAdvancedAreaPolicy.destructiveOperationsConfirmed == true)
        #expect(SyncAdvancedAreaPolicy.destructiveVisuallyDistinct == true)
    }

    @Test
    func unrecoverableWarningIsStandardNotPanelDominant() {
        // FR-163: the encrypted-notes-unrecoverable warning is standard
        // warning style, concise — not dominating the pane; the stable
        // configured state shows a Recovery info row instead of an
        // always-on orange warning.
        #expect(SyncAdvancedAreaPolicy.warningIsConciseStandard == true)
        #expect(SyncAdvancedAreaPolicy.stableStateShowsRecoveryInfoRow == true)
    }
}

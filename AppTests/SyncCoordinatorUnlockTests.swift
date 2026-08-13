import Testing
import Foundation
import os
import Domain
import Persistence
import SecurityCore
import SyncCore
@testable import StickyNotes

// MARK: - SyncCoordinator unlock tests (003 T179, FR-162a(b)/FR-053 Rev 2)
//
// Per tasks.md T179: the honest Locked state and the minimal unlock path.
// A configured vault whose remember-unlock is off MUST report locked after
// a relaunch (engine not wired); `unlock(password:)` restores the engine via
// a read-only remote bootstrap fetch (in-memory provider — no network);
// wrong password / missing configuration fail closed without state
// mutation.

/// Counts manifest fetches so the tests can prove the engine actually ran.
final class CountingManifestProvider: InMemorySyncProvider, @unchecked Sendable {
    private let counter = OSAllocatedUnfairLock(initialState: 0)
    var manifestFetches: Int { counter.withLock { $0 } }

    override func fetchManifest() async throws -> ManifestFetchResult {
        counter.withLock { $0 += 1 }
        return try await super.fetchManifest()
    }
}

@MainActor
@Suite struct SyncCoordinatorUnlockTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000009")!

    private func makeCoordinator(provider: InMemorySyncProvider) throws -> (SyncCoordinator, DatabaseStore, InMemorySecretStore) {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let secretStore = InMemorySecretStore()
        let coordinator = SyncCoordinator(
            store: store,
            secretStore: secretStore,
            deviceId: Self.deviceId,
            providerOverride: { _, _ in provider }
        )
        return (coordinator, store, secretStore)
    }

    private func configure(
        _ coordinator: SyncCoordinator,
        provider: InMemorySyncProvider,
        rememberUnlock: Bool
    ) async throws {
        try await coordinator.configure(
            providerType: .webdav,
            endpoint: "https://example.com/dav",
            containerPath: "stickynotes",
            bucket: nil,
            region: nil,
            credentials: SyncProviderCredentials(username: "user", password: "secret"),
            vaultPassword: "test-password",
            rememberUnlock: rememberUnlock,
            isTestFixture: true
        )
    }

    @Test
    func lockedAfterRelaunchWithoutRememberedUnlock() async throws {
        let provider = InMemorySyncProvider()
        let (coordinator, store, _) = try makeCoordinator(provider: provider)
        await coordinator.load()
        #expect(!coordinator.isConfigured)

        try await configure(coordinator, provider: provider, rememberUnlock: false)
        #expect(coordinator.isVaultUnlocked, "the configuring session holds the unlocked vault")

        // A relaunch with remember-off: a fresh coordinator over the same
        // store sees the configuration but cannot restore the master key.
        let reloaded = SyncCoordinator(
            store: store,
            secretStore: InMemorySecretStore(),
            deviceId: Self.deviceId,
            providerOverride: { _, _ in provider }
        )
        await reloaded.load()
        #expect(reloaded.isConfigured)
        #expect(!reloaded.isVaultUnlocked, "FR-053: the UI must see the Locked state, not a fake Configured")
    }

    @Test
    func unlockRestoresTheEngineAndSyncs() async throws {
        let provider = CountingManifestProvider()
        let (coordinator, store, _) = try makeCoordinator(provider: provider)
        await coordinator.load()
        try await configure(coordinator, provider: provider, rememberUnlock: false)

        let reloaded = SyncCoordinator(
            store: store,
            secretStore: InMemorySecretStore(),
            deviceId: Self.deviceId,
            providerOverride: { _, _ in provider }
        )
        await reloaded.load()
        #expect(!reloaded.isVaultUnlocked)

        // While locked there is no engine: a manual sync must not reach the
        // provider.
        let fetchesWhileLocked = provider.manifestFetches
        await reloaded.manualSync()
        #expect(provider.manifestFetches == fetchesWhileLocked, "no engine while locked")

        try await reloaded.unlock(password: "test-password")
        #expect(reloaded.isVaultUnlocked, "unlock wires the engine")

        await reloaded.manualSync()
        #expect(provider.manifestFetches > fetchesWhileLocked, "a manual sync actually runs after unlock")
        #expect(reloaded.lastErrorCode == nil)
    }

    @Test
    func unlockWrongPasswordFailsClosed() async throws {
        let provider = InMemorySyncProvider()
        let (coordinator, store, _) = try makeCoordinator(provider: provider)
        await coordinator.load()
        try await configure(coordinator, provider: provider, rememberUnlock: false)

        let reloaded = SyncCoordinator(
            store: store,
            secretStore: InMemorySecretStore(),
            deviceId: Self.deviceId,
            providerOverride: { _, _ in provider }
        )
        await reloaded.load()

        await #expect(throws: StickyError.self) {
            try await reloaded.unlock(password: "wrong-password")
        }
        #expect(!reloaded.isVaultUnlocked, "fail closed: no state mutation on wrong password")
    }

    @Test
    func unlockWithoutConfigurationFailsClosed() async throws {
        let provider = InMemorySyncProvider()
        let (coordinator, _, _) = try makeCoordinator(provider: provider)
        await coordinator.load()

        await #expect(throws: StickyError.self) {
            try await coordinator.unlock(password: "anything")
        }
        #expect(!coordinator.isVaultUnlocked)
    }
}

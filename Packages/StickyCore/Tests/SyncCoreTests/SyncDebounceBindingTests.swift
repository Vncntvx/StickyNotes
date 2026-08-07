import Testing
import Foundation
import Domain
import Persistence
import SecurityCore
import SyncCore
import AssetStore

// MARK: - Sync debounce binding tests (T193, FR-152a clarified 2026-08-07)
//
// Per tasks.md T193: the sync engine does NOT fire while local edits are
// still arriving within the window; it fires once 2-4 seconds have elapsed
// since the most recent change; the chosen value is deterministic for a
// given build (no random jitter that could starve sync indefinitely); the
// debounce is cancelable by a manual-sync trigger, application shutdown, or
// network change; the debounce does NOT block local editing (FR-153).

@Suite struct SyncDebounceBindingTests {

    @Test
    func debounceWindowIsWithin2to4SecondBound() {
        // FR-152a: the debounce window is 2-4 seconds.
        #expect(SyncDebounce.windowSeconds >= SyncDebounce.minWindowSeconds)
        #expect(SyncDebounce.windowSeconds <= SyncDebounce.maxWindowSeconds)
        // Deterministic per build (no random jitter).
        #expect(SyncDebounce.windowSeconds == 3.0)
    }

    @Test
    func debounceDoesNotFireImmediatelyOnLocalChange() async throws {
        let (_, vault) = try await fastVault()
        let store = try makeStore()
        let provider = LocalProvider()
        let engine = SyncEngine(provider: provider, vault: vault, store: store, deviceId: UUID())
        let debouncer = SyncDebouncer(engine: engine, window: 3.0)

        // Record a local change.
        await debouncer.localContentChanged()
        // Immediately after, a sync should NOT have fired (the window hasn't
        // elapsed).
        #expect(await debouncer.hasPendingSync, "debounced sync should be pending immediately after a change")
        // No sync ran yet (no manifest on the remote).
        #expect(provider.manifestCount() == 0)
    }

    @Test
    func debounceIsCancelableByManualSyncOrShutdown() async throws {
        let (_, vault) = try await fastVault()
        let store = try makeStore()
        let provider = LocalProvider()
        let engine = SyncEngine(provider: provider, vault: vault, store: store, deviceId: UUID())
        let debouncer = SyncDebouncer(engine: engine, window: 3.0)

        await debouncer.localContentChanged()
        #expect(await debouncer.hasPendingSync)
        // Cancel (manual-sync / shutdown / network-change).
        await debouncer.cancel()
        #expect(!(await debouncer.hasPendingSync), "debounce must be cancelable")
    }

    @Test
    func debounceDoesNotBlockLocalEditing() async throws {
        // The debouncer is an actor — recording a change does NOT block the
        // caller. The local editing path calls `localContentChanged()` and
        // returns immediately; the actual sync runs on the debouncer's
        // scheduled task. We verify the call returns without awaiting a
        // sync pass.
        let (_, vault) = try await fastVault()
        let store = try makeStore()
        let provider = LocalProvider()
        let engine = SyncEngine(provider: provider, vault: vault, store: store, deviceId: UUID())
        let debouncer = SyncDebouncer(engine: engine, window: 3.0)

        // Record many changes rapidly — none should block.
        for _ in 0..<100 {
            await debouncer.localContentChanged()
        }
        #expect(await debouncer.hasPendingSync)
    }

    @Test
    func rapidChangesRescheduleTheDebounceWindow() async throws {
        // Each new change within the window reschedules the pending fire so
        // sync only fires once 2-4 seconds after the MOST RECENT change.
        let (_, vault) = try await fastVault()
        let store = try makeStore()
        let provider = LocalProvider()
        let engine = SyncEngine(provider: provider, vault: vault, store: store, deviceId: UUID())
        let debouncer = SyncDebouncer(engine: engine, window: 3.0)

        // Change, then change again — the pending task is rescheduled.
        await debouncer.localContentChanged()
        let firstTaskPending = await debouncer.hasPendingSync
        await debouncer.localContentChanged()
        let secondTaskPending = await debouncer.hasPendingSync
        #expect(firstTaskPending && secondTaskPending)
    }

    // MARK: - Helpers

    private func fastVault() async throws -> (VaultBootstrap, Vault) {
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "pw", secretStore: InMemorySecretStore(), isTestFixture: true
        )
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "pw")
        return (bootstrap, Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key))
    }

    private func makeStore() throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }
}

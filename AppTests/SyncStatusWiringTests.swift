import Testing
import Foundation
import Domain
import Persistence
import SecurityCore
@testable import StickyNotes

// MARK: - R1.6 sync status wiring (remediation-phase1 T024/T025)
//
// The banner previously hardcoded `vaultLocked: false` (the needsUnlock
// category was unreachable in production — audit S-4/S-5) and 4 of 5
// banner action buttons were silent no-ops (`default: break`). These tests
// pin the wiring: locked vault → .needsUnlock banner; every banner action
// dispatches to its wired handler.

@MainActor
@Suite struct SyncStatusWiringTests {

    private func makeEnvironment() throws -> (AppEnvironment, SyncCoordinator) {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let coordinator = SyncCoordinator(
            store: store,
            secretStore: InMemorySecretStore(),
            deviceId: UUID()
        )
        let env = AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(
                defaults: UserDefaults(suiteName: "test.banner.\(UUID().uuidString)") ?? .standard
            ),
            syncCoordinator: coordinator
        )
        return (env, coordinator)
    }

    @Test
    func lockedVaultSurfacesNeedsUnlockBanner() async throws {
        // A configured-but-locked vault (configuration persisted, no unlock
        // performed → the coordinator holds no vault) MUST surface the
        // .needsUnlock banner.
        let (env, coordinator) = try makeEnvironment()
        // Persist a configuration so the coordinator is "configured".
        let configStore = SQLiteVaultConfigurationStore(store: env.persistence.store!)
        try await configStore.saveConfiguration(VaultConfiguration(
            vaultId: UUID(),
            vaultLocator: RemoteLayout.opaqueObjectName(),
            providerType: .webdav,
            providerConfig: RedactedSyncConfig(endpoint: "https://example.com"),
            keychainCredentialRef: "test-ref",
            rememberedUnlock: .disabled
        ))
        await coordinator.load()
        let model = LibraryModel(environment: env)
        #expect(model.syncCoordinator?.isConfigured == true, "precondition: vault is configured")
        #expect(model.syncCoordinator?.isVaultUnlocked == false, "precondition: vault is locked")

        model.refreshBanner()
        #expect(model.bannerState.current?.category == .needsUnlock,
                "a locked vault must surface the needsUnlock banner (not clear it)")
    }

    @Test
    func bannerActionsDispatchToWiredHandlers() throws {
        let (env, _) = try makeEnvironment()
        let model = LibraryModel(environment: env)
        var settingsOpened = 0
        var conflictsRevealed = 0
        model.onOpenSyncSettings = { settingsOpened += 1 }
        model.onRevealConflicts = { conflictsRevealed += 1 }

        // needsUnlock → open sync settings (where the unlock flow lives).
        model.bannerState.present(category: .needsUnlock)
        model.performBannerAction()
        #expect(settingsOpened == 1, ".needsUnlock must open the sync settings")

        // authFailed → re-authenticate lives in the sync settings.
        model.bannerState.present(category: .authFailed)
        model.performBannerAction()
        #expect(settingsOpened == 2, ".authFailed must open the sync settings")

        // repositoryDamaged → advanced recovery lives in the sync settings.
        model.bannerState.present(category: .repositoryDamaged)
        model.performBannerAction()
        #expect(settingsOpened == 3, ".repositoryDamaged must open the sync settings")

        // conflictCopiesCreated → reveal the conflict copies surface.
        model.bannerState.present(category: .conflictCopiesCreated)
        model.performBannerAction()
        #expect(conflictsRevealed == 1, ".conflictCopiesCreated must reveal conflicts")

        // cannotConnect keeps the manual-sync path (settings NOT opened).
        model.bannerState.present(category: .cannotConnect)
        model.performBannerAction()
        #expect(settingsOpened == 3, ".cannotConnect must not open the settings")
    }
}

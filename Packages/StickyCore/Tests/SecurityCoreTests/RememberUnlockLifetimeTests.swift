import Testing
import Foundation
import CryptoKit
import Domain
import SecurityCore

// MARK: - Remember-unlock lifetime tests (T177, FR-162a clarified 2026-08-07)
//
// Per tasks.md T177: remember-unlock enabled → relaunch app → vault still
// unlocked without password re-entry; logout or restart → vault locked,
// password required; explicit lock → Keychain item cleared; password
// forgotten → unrecoverable even with remember-unlock on (FR-163); the app
// MUST NOT behave as a login-item-bound daemon that keeps the vault unlocked
// across system restarts.

@Suite struct RememberUnlockLifetimeTests {

    private func fastBootstrap(password: String = "pw") async throws -> (VaultBootstrap, SymmetricKey) {
        let bootstrap = try await VaultBootstrapService.createVault(
            password: password, secretStore: InMemorySecretStore(), isTestFixture: true
        )
        let key = try await VaultBootstrapService.openVault(bootstrap, password: password)
        return (bootstrap, key)
    }

    private func makeConfig(vaultId: UUID, rememberedUnlock: RememberedUnlock = .enabledUntilLockOrRestart, keychainRef: String? = "ref", bootTimestamp: Int? = 1000) -> VaultConfiguration {
        VaultConfiguration(
            vaultId: vaultId,
            vaultLocator: "locator",
            providerType: .webdav,
            providerConfig: RedactedSyncConfig(endpoint: "https://example", region: nil, bucket: nil, prefix: nil),
            keychainCredentialRef: "cred-ref",
            rememberedUnlock: rememberedUnlock,
            rememberedUnlockKeychainRef: keychainRef,
            rememberedUnlockBootTimestamp: bootTimestamp
        )
    }

    // MARK: - Enable remember-unlock

    @Test
    func enableRememberUnlockStoresKeyInKeychain() async throws {
        let (bootstrap, key) = try await fastBootstrap()
        let store = InMemorySecretStore()
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let config = makeConfig(vaultId: bootstrap.vaultId, keychainRef: nil, bootTimestamp: nil)
        let (ref, bootTs) = try VaultBootstrapService.enableRememberUnlock(
            vault: vault, configuration: config, bootTimestamp: 5000, secretStore: store
        )
        #expect(!ref.isEmpty)
        #expect(bootTs == 5000)
        // The key is stored under the ref.
        let stored = try store.load(forKey: ref)
        #expect(stored != nil)
        #expect(stored?.count == 32)
    }

    // MARK: - App-launch silent restore (boot timestamp matches)

    @Test
    func launchUnlockSucceedsWhenBootTimestampMatches() async throws {
        let (bootstrap, key) = try await fastBootstrap()
        let store = InMemorySecretStore()
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let (ref, _) = try VaultBootstrapService.enableRememberUnlock(
            vault: vault, configuration: makeConfig(vaultId: bootstrap.vaultId), bootTimestamp: 5000, secretStore: store
        )
        let config = makeConfig(vaultId: bootstrap.vaultId, keychainRef: ref, bootTimestamp: 5000)
        let restored = try VaultBootstrapService.attemptLaunchUnlock(
            bootstrap: bootstrap, configuration: config, currentBootTimestamp: 5000, secretStore: store
        )
        #expect(restored != nil)
        #expect(restored?.vaultId == bootstrap.vaultId)
    }

    @Test
    func launchUnlockPromptsWhenBootTimestampDiffers() async throws {
        // Mac restarted → boot timestamp differs → password required.
        let (bootstrap, key) = try await fastBootstrap()
        let store = InMemorySecretStore()
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let (ref, _) = try VaultBootstrapService.enableRememberUnlock(
            vault: vault, configuration: makeConfig(vaultId: bootstrap.vaultId), bootTimestamp: 5000, secretStore: store
        )
        let config = makeConfig(vaultId: bootstrap.vaultId, keychainRef: ref, bootTimestamp: 5000)
        let restored = try VaultBootstrapService.attemptLaunchUnlock(
            bootstrap: bootstrap, configuration: config, currentBootTimestamp: 9999, secretStore: store
        )
        #expect(restored == nil, "restart (different boot timestamp) must require password")
    }

    @Test
    func launchUnlockPromptsWhenRememberDisabled() async throws {
        let (bootstrap, _) = try await fastBootstrap()
        let store = InMemorySecretStore()
        let config = makeConfig(vaultId: bootstrap.vaultId, rememberedUnlock: .disabled, keychainRef: nil, bootTimestamp: nil)
        let restored = try VaultBootstrapService.attemptLaunchUnlock(
            bootstrap: bootstrap, configuration: config, currentBootTimestamp: 5000, secretStore: store
        )
        #expect(restored == nil, "remember disabled → prompt for password")
    }

    @Test
    func launchUnlockPromptsWhenKeychainItemMissing() async throws {
        let (bootstrap, key) = try await fastBootstrap()
        let store = InMemorySecretStore() // empty — no stored key
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        _ = try VaultBootstrapService.enableRememberUnlock(
            vault: vault, configuration: makeConfig(vaultId: bootstrap.vaultId), bootTimestamp: 5000, secretStore: InMemorySecretStore()
        )
        let config = makeConfig(vaultId: bootstrap.vaultId, keychainRef: "ref", bootTimestamp: 5000)
        let restored = try VaultBootstrapService.attemptLaunchUnlock(
            bootstrap: bootstrap, configuration: config, currentBootTimestamp: 5000, secretStore: store
        )
        #expect(restored == nil, "missing Keychain item → prompt for password")
    }

    // MARK: - Explicit lock clears Keychain

    @Test
    func explicitLockClearsKeychainItem() async throws {
        let (bootstrap, key) = try await fastBootstrap()
        let store = InMemorySecretStore()
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let (ref, _) = try VaultBootstrapService.enableRememberUnlock(
            vault: vault, configuration: makeConfig(vaultId: bootstrap.vaultId), bootTimestamp: 5000, secretStore: store
        )
        #expect(try store.load(forKey: ref) != nil)
        let config = makeConfig(vaultId: bootstrap.vaultId, keychainRef: ref, bootTimestamp: 5000)
        try VaultBootstrapService.lockVault(configuration: config, secretStore: store)
        #expect(try store.load(forKey: ref) == nil, "explicit lock must clear the Keychain item")
    }

    // MARK: - Password forgotten is unrecoverable (FR-163)

    @Test
    func forgottenPasswordIsUnrecoverableEvenWithRememberUnlockOn() async throws {
        // If the Keychain item is gone (e.g., user wiped Keychain) AND the
        // password is forgotten, the vault cannot be opened. Remember-unlock
        // does not bypass FR-163.
        let (bootstrap, _) = try await fastBootstrap()
        let store = InMemorySecretStore() // no stored remembered key
        let config = makeConfig(vaultId: bootstrap.vaultId, keychainRef: "missing-ref", bootTimestamp: 5000)
        let restored = try VaultBootstrapService.attemptLaunchUnlock(
            bootstrap: bootstrap, configuration: config, currentBootTimestamp: 5000, secretStore: store
        )
        #expect(restored == nil, "forgotten password + missing Keychain item → unrecoverable")
        // And a wrong password still fails closed.
        do {
            _ = try await VaultBootstrapService.openVault(bootstrap, password: "forgotten-wrong")
            Issue.record("wrong password must fail closed")
        } catch StickyError.encryption(.wrongPassword) {
            #expect(true)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // MARK: - Not a login-item daemon

    @Test
    func rememberUnlockDoesNotSurviveRestart() async throws {
        // The boot-timestamp comparison is the sole restart-detection
        // mechanism. After restart, the timestamp differs → password
        // required. The app is NOT a login-item-bound daemon.
        let (bootstrap, key) = try await fastBootstrap()
        let store = InMemorySecretStore()
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let (ref, oldBoot) = try VaultBootstrapService.enableRememberUnlock(
            vault: vault, configuration: makeConfig(vaultId: bootstrap.vaultId), bootTimestamp: 1000, secretStore: store
        )
        // Simulate restart: boot timestamp changes.
        let config = makeConfig(vaultId: bootstrap.vaultId, keychainRef: ref, bootTimestamp: oldBoot)
        let restoredAfterRestart = try VaultBootstrapService.attemptLaunchUnlock(
            bootstrap: bootstrap, configuration: config, currentBootTimestamp: 2000, secretStore: store
        )
        #expect(restoredAfterRestart == nil, "restart must require password (not a daemon)")
    }
}

import Testing
import Foundation
import CryptoKit
import Domain
import SecurityCore

// MARK: - Remember-unlock toggle-off tests (T216, FR-162a clarified 2026-08-07)
//
// Per tasks.md T216: toggling `rememberedUnlock` from
// `enabledUntilLockOrRestart` to `disabled` while the vault is currently
// unlocked: (a) immediately removes the remembered key from Keychain (clears
// `rememberedUnlockKeychainRef` and `rememberedUnlockBootTimestamp`); (b)
// preserves the current unlocked vault state in memory (no re-prompt, no
// forced lock); (c) a subsequent app launch (without restart) prompts for
// the password (Keychain item gone); (d) explicit lock still works and
// clears the in-memory key. The app MUST NOT force a re-prompt merely
// because the setting was toggled off.

@Suite struct RememberUnlockToggleTests {

    private func fastBootstrap(password: String = "pw") async throws -> (VaultBootstrap, SymmetricKey) {
        let bootstrap = try await VaultBootstrapService.createVault(
            password: password, secretStore: InMemorySecretStore(), isTestFixture: true
        )
        let key = try await VaultBootstrapService.openVault(bootstrap, password: password)
        return (bootstrap, key)
    }

    private func makeConfig(vaultId: UUID, keychainRef: String? = "ref", bootTimestamp: Int? = 1000) -> VaultConfiguration {
        VaultConfiguration(
            vaultId: vaultId,
            vaultLocator: "locator",
            providerType: .webdav,
            providerConfig: RedactedSyncConfig(endpoint: "https://example", region: nil, bucket: nil, prefix: nil),
            keychainCredentialRef: "cred-ref",
            rememberedUnlock: .enabledUntilLockOrRestart,
            rememberedUnlockKeychainRef: keychainRef,
            rememberedUnlockBootTimestamp: bootTimestamp
        )
    }

    @Test
    func toggleOffRemovesRememberedKeyFromKeychain() async throws {
        let (bootstrap, key) = try await fastBootstrap()
        let store = InMemorySecretStore()
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let (ref, _) = try VaultBootstrapService.enableRememberUnlock(
            vault: vault, configuration: makeConfig(vaultId: bootstrap.vaultId), bootTimestamp: 1000, secretStore: store
        )
        #expect(try store.load(forKey: ref) != nil)

        // Toggle off.
        let config = makeConfig(vaultId: bootstrap.vaultId, keychainRef: ref, bootTimestamp: 1000)
        try VaultBootstrapService.disableRememberUnlock(configuration: config, secretStore: store)

        // (a) Keychain item removed.
        #expect(try store.load(forKey: ref) == nil, "toggle-off must remove the remembered key from Keychain")
    }

    @Test
    func toggleOffPreservesCurrentUnlockedVaultState() async throws {
        let (bootstrap, key) = try await fastBootstrap()
        let store = InMemorySecretStore()
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let (ref, _) = try VaultBootstrapService.enableRememberUnlock(
            vault: vault, configuration: makeConfig(vaultId: bootstrap.vaultId), bootTimestamp: 1000, secretStore: store
        )

        // Toggle off.
        let config = makeConfig(vaultId: bootstrap.vaultId, keychainRef: ref, bootTimestamp: 1000)
        try VaultBootstrapService.disableRememberUnlock(configuration: config, secretStore: store)

        // (b) The vault is still usable in memory — the master key is still
        // valid (no forced re-prompt). We verify by encrypting/decrypting an
        // object with the existing vault instance.
        let envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("still unlocked".utf8)
        )
        let decrypted = try vault.decrypt(envelope: envelope, objectType: "note", schemaVersion: 1)
        #expect(decrypted.plaintext == Data("still unlocked".utf8))
    }

    @Test
    func toggleOffPromptsOnNextLaunchWithoutRestart() async throws {
        let (bootstrap, key) = try await fastBootstrap()
        let store = InMemorySecretStore()
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let (ref, bootTs) = try VaultBootstrapService.enableRememberUnlock(
            vault: vault, configuration: makeConfig(vaultId: bootstrap.vaultId), bootTimestamp: 1000, secretStore: store
        )

        // Toggle off — clears the Keychain item.
        let configEnabled = makeConfig(vaultId: bootstrap.vaultId, keychainRef: ref, bootTimestamp: bootTs)
        try VaultBootstrapService.disableRememberUnlock(configuration: configEnabled, secretStore: store)

        // Simulate the updated configuration after toggle-off (the App layer
        // clears the ref + boot timestamp on the persisted VaultConfiguration).
        let configDisabled = VaultConfiguration(
            vaultId: bootstrap.vaultId,
            vaultLocator: "locator",
            providerType: .webdav,
            providerConfig: RedactedSyncConfig(endpoint: "https://example", region: nil, bucket: nil, prefix: nil),
            keychainCredentialRef: "cred-ref",
            rememberedUnlock: .disabled,
            rememberedUnlockKeychainRef: nil,
            rememberedUnlockBootTimestamp: nil
        )

        // (c) Subsequent launch (same boot timestamp — no restart) prompts
        // for password because the Keychain item is gone and remember is
        // disabled.
        let restored = try VaultBootstrapService.attemptLaunchUnlock(
            bootstrap: bootstrap, configuration: configDisabled,
            currentBootTimestamp: bootTs, secretStore: store
        )
        #expect(restored == nil, "launch after toggle-off must prompt for password")
    }

    @Test
    func explicitLockStillWorksAfterToggleOff() async throws {
        let (bootstrap, key) = try await fastBootstrap()
        let store = InMemorySecretStore()
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let (ref, _) = try VaultBootstrapService.enableRememberUnlock(
            vault: vault, configuration: makeConfig(vaultId: bootstrap.vaultId), bootTimestamp: 1000, secretStore: store
        )

        // Toggle off first.
        let configEnabled = makeConfig(vaultId: bootstrap.vaultId, keychainRef: ref, bootTimestamp: 1000)
        try VaultBootstrapService.disableRememberUnlock(configuration: configEnabled, secretStore: store)

        // Explicit lock is idempotent — it clears the Keychain item (already
        // gone) and does not throw.
        let configDisabled = VaultConfiguration(
            vaultId: bootstrap.vaultId,
            vaultLocator: "locator",
            providerType: .webdav,
            providerConfig: RedactedSyncConfig(endpoint: "https://example", region: nil, bucket: nil, prefix: nil),
            keychainCredentialRef: "cred-ref",
            rememberedUnlock: .disabled,
            rememberedUnlockKeychainRef: nil,
            rememberedUnlockBootTimestamp: nil
        )
        #expect(throws: Never.self) {
            try VaultBootstrapService.lockVault(configuration: configDisabled, secretStore: store)
        }
    }

    @Test
    func toggleOffDoesNotForceRePromptForCurrentSession() async throws {
        // The defining behavior: toggling off does NOT force a re-prompt
        // merely because the setting changed. The vault stays unlocked in
        // memory. This is verified by the fact that disableRememberUnlock
        // only touches the Keychain — it never invalidates the Vault
        // instance. The caller continues to use the same vault.
        let (bootstrap, key) = try await fastBootstrap()
        let store = InMemorySecretStore()
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
        let (ref, _) = try VaultBootstrapService.enableRememberUnlock(
            vault: vault, configuration: makeConfig(vaultId: bootstrap.vaultId), bootTimestamp: 1000, secretStore: store
        )
        // Toggle off.
        try VaultBootstrapService.disableRememberUnlock(
            configuration: makeConfig(vaultId: bootstrap.vaultId, keychainRef: ref, bootTimestamp: 1000),
            secretStore: store
        )
        // The vault instance is unchanged — still usable.
        #expect(vault.vaultId == bootstrap.vaultId)
        let envelope = try vault.encrypt(
            objectId: UUID().uuidString, objectType: "note", schemaVersion: 1,
            plaintext: Data("no re-prompt".utf8)
        )
        let back = try vault.decrypt(envelope: envelope, objectType: "note", schemaVersion: 1)
        #expect(back.plaintext == Data("no re-prompt".utf8))
    }
}

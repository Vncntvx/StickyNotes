import Foundation
import CryptoKit
import Domain

// MARK: - VaultBootstrap (T112)
//
// Per contracts/vault-bootstrap.schema.json and plan §Encryption
// architecture:
//
// - Versioned bootstrap: format version, random vault ID, random vault
//   locator, Argon2id salt + params, wrapped master key, optional
//   key-confirmation material, encryption-suite version.
// - The password protects the RANDOM MASTER KEY (not every object).
// - Password change RE-WRAPS the master key; unchanged objects are not
//   re-encrypted (FR-164).
// - Wrong password / corrupt bootstrap fail closed.

/// The vault bootstrap (vault-bootstrap.schema.json, version 1).
public struct VaultBootstrap: Sendable, Equatable, Codable {
    public static let schemaVersion = 1
    public static let currentFormatVersion = 1

    public var schemaVersion: Int
    public var formatVersion: Int
    public var vaultId: UUID
    /// Random/opaque remote locator — reveals nothing semantic.
    public var vaultLocator: String
    public var argon2id: Argon2Parameters
    /// Master key wrapped with the password-derived KEK.
    public var wrappedMasterKey: WrappedKey
    /// Optional wrong-password verification material.
    public var keyConfirmation: WrappedKey?
    public var encryptionSuiteVersion: Int
    public var createdAt: Date

    public struct WrappedKey: Sendable, Equatable, Codable {
        public var nonce: Data
        public var sealed: Data  // AES-GCM combined (ciphertext + tag)

        public init(nonce: Data, sealed: Data) {
            self.nonce = nonce
            self.sealed = sealed
        }
    }

    public init(
        schemaVersion: Int = VaultBootstrap.schemaVersion,
        formatVersion: Int = VaultBootstrap.currentFormatVersion,
        vaultId: UUID,
        vaultLocator: String,
        argon2id: Argon2Parameters,
        wrappedMasterKey: WrappedKey,
        keyConfirmation: WrappedKey? = nil,
        encryptionSuiteVersion: Int = EncryptionSuite.version,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.formatVersion = formatVersion
        self.vaultId = vaultId
        self.vaultLocator = vaultLocator
        self.argon2id = argon2id
        self.wrappedMasterKey = wrappedMasterKey
        self.keyConfirmation = keyConfirmation
        self.encryptionSuiteVersion = encryptionSuiteVersion
        self.createdAt = createdAt
    }

    /// Canonical JSON encoding (stable keys, explicit schemaVersion).
    public func canonicalJSON() throws -> Data {
        // R3.3 (remediation roadmap 2026-08-15): converged on
        // Domain.CanonicalJSONEncoder — canonical dates are ISO 8601 UTC
        // with millisecond precision + `Z` (the previous .iso8601 strategy
        // dropped fractional seconds, producing different bytes than every
        // other canonical boundary).
        try CanonicalJSONEncoder().encode(self)
    }

    public static func fromCanonicalJSON(_ data: Data) throws -> VaultBootstrap {
        let decoder = CanonicalJSONDecoder()
        guard let decoded = try? decoder.decode(VaultBootstrap.self, from: data) else {
            throw StickyError.encryption(.corruptBootstrap)
        }
        guard decoded.schemaVersion == VaultBootstrap.schemaVersion else {
            throw StickyError.encryption(.corruptBootstrap)
        }
        return decoded
    }
}

/// Creates/opens a vault. Stateless; secrets live in the caller-provided
/// SecretStore (Keychain in production).
public enum VaultBootstrapService {

    /// Creates a new vault: random vault ID + locator, random salt, random
    /// master key, KEK-wrapped master key + key-confirmation blob.
    ///
    /// Per FR-160c (clarified 2026-08-07): the Argon2id parameters MUST meet
    /// the production minimums (memory ≥ 19456 KiB, iterations ≥ 2,
    /// parallelism ≥ 1) unless `isTestFixture` is explicitly true. The
    /// default `Argon2Parameters.recommended` (64 MiB / 3 / 4) exceeds the
    /// minimums; the guard makes the requirement explicit so a future caller
    /// cannot accidentally use weaker params.
    public static func createVault(
        password: String,
        secretStore: any SecretStore,
        isTestFixture: Bool = false
    ) async throws -> VaultBootstrap {
        let salt = try KeyDerivation.generateSalt()
        // When isTestFixture is true, use fast Argon2id params (64 KiB) to
        // keep the test suite fast. The production-minimum guard is bypassed.
        // When false, use the OWASP-recommended params (64 MiB) and enforce
        // the FR-160c production minimums.
        var parameters: Argon2Parameters
        if isTestFixture {
            parameters = Argon2Parameters(salt: salt, memoryKiB: 64, iterations: 2, parallelism: 2)
        } else {
            parameters = Argon2Parameters.recommended
            parameters.salt = salt
            try parameters.requireProductionMinimum(isTestFixture: false)
        }

        let kek = try await KeyDerivation.deriveKEK(password: password, parameters: parameters)
        let masterKey = KeyDerivation.generateMasterKey()

        // Key confirmation: wrap a deterministic marker with the KEK so a
        // wrong password is detected without touching objects.
        let confirmationMarker = Data("sticky-vault-confirmation-v1".utf8)
        let (confNonce, confSealed) = try ObjectCrypto.wrap(masterKeyBytes: confirmationMarker, kek: kek)
        let (masterNonce, masterSealed) = try ObjectCrypto.wrap(
            masterKeyBytes: masterKey.withUnsafeBytes { Data($0) },
            kek: kek
        )

        let bootstrap = VaultBootstrap(
            vaultId: UUID(),
            vaultLocator: RemoteLayout.opaqueObjectName(),
            argon2id: parameters,
            wrappedMasterKey: VaultBootstrap.WrappedKey(nonce: masterNonce, sealed: masterSealed),
            keyConfirmation: VaultBootstrap.WrappedKey(nonce: confNonce, sealed: confSealed)
        )
        // R1.3 (remediation roadmap 2026-08-14): previously this saved the
        // raw master key under a dedicated Keychain item that NOTHING ever
        // read and NOTHING ever deleted — dead key material permanently
        // bypassing the password. The only legitimate persisted master key
        // is the remembered-unlock item, written explicitly by
        // `enableRememberUnlock` with its own lifecycle (deleted by
        // `lockVault`/`disableRememberUnlock`). The wrapped master key
        // above is the persistence contract: the password (KEK) protects
        // the random master key.
        return bootstrap
    }

    /// Opens the vault: derives the KEK from the password, verifies the
    /// key-confirmation blob (wrong password → `.encryption(.wrongPassword)`
    /// BEFORE any object decryption), unwraps the master key.
    public static func openVault(
        _ bootstrap: VaultBootstrap,
        password: String
    ) async throws -> SymmetricKey {
        // Unsupported suite/format → fail closed, never partial.
        guard bootstrap.encryptionSuiteVersion == EncryptionSuite.version else {
            throw StickyError.encryption(.unsupportedEnvelopeVersion)
        }
        guard bootstrap.formatVersion == VaultBootstrap.currentFormatVersion else {
            throw StickyError.encryption(.unsupportedEnvelopeVersion)
        }

        let kek = try await KeyDerivation.deriveKEK(password: password, parameters: bootstrap.argon2id)

        // Wrong-password detection via key confirmation.
        if let confirmation = bootstrap.keyConfirmation {
            do {
                _ = try ObjectCrypto.unwrap(
                    masterKeyBytes: confirmation.sealed,
                    nonce: confirmation.nonce,
                    kek: kek
                )
            } catch {
                throw StickyError.encryption(.wrongPassword)
            }
        }

        let masterKeyBytes = try ObjectCrypto.unwrap(
            masterKeyBytes: bootstrap.wrappedMasterKey.sealed,
            nonce: bootstrap.wrappedMasterKey.nonce,
            kek: kek
        )
        return SymmetricKey(data: masterKeyBytes)
    }

    /// Password change: re-wraps the master key with the new password's KEK.
    /// Objects are NOT re-encrypted (FR-164). Returns the updated bootstrap.
    public static func changePassword(
        _ bootstrap: VaultBootstrap,
        currentPassword: String,
        newPassword: String
    ) async throws -> VaultBootstrap {
        let oldKEK = try await KeyDerivation.deriveKEK(password: currentPassword, parameters: bootstrap.argon2id)
        // Unwrapping the master key validates the current password.
        let masterKeyBytes = try ObjectCrypto.unwrap(
            masterKeyBytes: bootstrap.wrappedMasterKey.sealed,
            nonce: bootstrap.wrappedMasterKey.nonce,
            kek: oldKEK
        )

        // Fresh salt + params for the new password.
        let salt = try KeyDerivation.generateSalt()
        var parameters = Argon2Parameters.recommended
        parameters.salt = salt
        let newKEK = try await KeyDerivation.deriveKEK(password: newPassword, parameters: parameters)

        var updated = bootstrap
        updated.argon2id = parameters
        let (newNonce, newSealed) = try ObjectCrypto.wrap(masterKeyBytes: masterKeyBytes, kek: newKEK)
        updated.wrappedMasterKey = VaultBootstrap.WrappedKey(nonce: newNonce, sealed: newSealed)
        // Re-wrap the key confirmation with the new KEK.
        let confirmationMarker = Data("sticky-vault-confirmation-v1".utf8)
        let (confNonce, confSealed) = try ObjectCrypto.wrap(masterKeyBytes: confirmationMarker, kek: newKEK)
        updated.keyConfirmation = VaultBootstrap.WrappedKey(nonce: confNonce, sealed: confSealed)
        return updated
    }
}

// MARK: - Wrong-vault detection (T181, FR edge case clarified 2026-08-07)
//
// Per contracts/vault-bootstrap.schema.json + contracts/provider-errors.md
// `wrongVault` category: when fetching/bootstrap-checking a repository, the
// bootstrap object's `vaultId` is authoritative. If it does not match the
// locally-configured `VaultConfiguration.vaultId` (or a bootstrap already
// exists under the chosen locator for a new vault), the app MUST fail closed
// with a typed `wrongVault` error and MUST NOT modify any local or remote
// data. Starting a new empty vault on a repo that already contains a
// different vault's bootstrap bootstraps under a new random locator WITHOUT
// overwriting the existing one.

public extension VaultBootstrapService {

    /// Opens a REMOTE bootstrap fetched during the join flow (T007, plan
    /// §Join flow): parse → key-confirmation (wrong password fails closed,
    /// distinguishable from vault-not-found) → optional vaultId context
    /// check (wrong-vault fails closed). Reuses the verified `openVault`
    /// internals — no parallel verification path.
    ///
    /// - Parameters:
    ///   - remoteBootstrap: The bootstrap object fetched from the remote
    ///     (raw wire bytes).
    ///   - password: The synchronization password entered by the user.
    ///   - expectedVaultId: The locally-retained `VaultConfiguration.vaultId`
    ///     when one exists (nil for a device with no prior config). A
    ///     mismatch fails closed with `.credentials(.wrongVault)`.
    /// - Returns: The unwrapped master key.
    static func openRemoteBootstrap(
        remoteBootstrap wire: Data,
        password: String,
        expectedVaultId: UUID?
    ) async throws -> SymmetricKey {
        // Parse + schema/format validation (fail closed on corrupt data).
        let bootstrap = try VaultBootstrap.fromCanonicalJSON(wire)
        return try await openRemoteBootstrap(
            remoteBootstrap: bootstrap,
            password: password,
            expectedVaultId: expectedVaultId
        )
    }

    /// Opens a REMOTE bootstrap fetched during the join flow (T007). Same
    /// semantics as the wire-bytes variant, for callers that already parsed.
    static func openRemoteBootstrap(
        remoteBootstrap bootstrap: VaultBootstrap,
        password: String,
        expectedVaultId: UUID?
    ) async throws -> SymmetricKey {
        // Wrong-vault context check BEFORE any key derivation: a bootstrap
        // from a different vault must fail closed without touching anything.
        if let expected = expectedVaultId {
            try checkBootstrap(bootstrap, matches: expected)
        }
        return try await openVault(bootstrap, password: password)
    }

    /// Checks whether a fetched bootstrap belongs to the locally-configured
    /// vault. Throws `.credentials(.wrongVault)` on mismatch. Does NOT
    /// modify any local or remote data.
    ///
    /// - Parameters:
    ///   - bootstrap: The bootstrap object fetched from the remote.
    ///   - configuredVaultId: The locally-configured `VaultConfiguration.vaultId`.
    static func checkBootstrap(
        _ bootstrap: VaultBootstrap,
        matches configuredVaultId: UUID
    ) throws {
        guard bootstrap.vaultId == configuredVaultId else {
            throw StickyError.credentials(.wrongVault)
        }
    }

    /// Checks whether a chosen locator is safe for starting a brand-new
    /// vault. If a bootstrap already exists under the locator AND its
    /// `vaultId` differs from any provided existing-vault id, the app MUST
    /// fail closed — the user must choose a different repository or start
    /// under a fresh random locator. Starting under a fresh locator
    /// bootstraps alongside the existing one without overwriting it.
    ///
    /// - Parameters:
    ///   - existingBootstrap: The bootstrap fetched from the chosen locator
    ///     (nil if the locator is empty — the normal new-vault case).
    ///   - existingVaultId: The vaultId the caller expects, if any (nil for
    ///     a brand-new vault where no local config exists yet).
    static func checkNewVaultLocator(
        existingBootstrap: VaultBootstrap?,
        existingVaultId: UUID?
    ) throws {
        guard let existing = existingBootstrap else {
            // Locator is empty — safe to start a new vault here.
            return
        }
        // A bootstrap exists under the locator. If it matches the caller's
        // expected vaultId, this is an open-existing-vault flow, not a
        // new-vault flow — the caller should use openVault, not createVault.
        if let expected = existingVaultId, existing.vaultId == expected {
            throw StickyError.credentials(.wrongVault)
        }
        // A bootstrap exists under the locator with a DIFFERENT vaultId —
        // fail closed. The user must choose a different repository or start
        // under a fresh random locator (which bootstraps alongside this
        // existing one without overwriting it).
        throw StickyError.credentials(.wrongVault)
    }

    /// Starts a new empty vault under a fresh random locator, guaranteed not
    /// to overwrite an existing bootstrap that may already live under a
    /// different locator on the same repository. The caller MUST have first
    /// verified (via `checkNewVaultLocator`) that the chosen locator is
    /// empty or that a fresh locator is warranted. This method always
    /// generates a NEW random locator, so it is safe to call even when
    /// another vault's bootstrap exists elsewhere on the repository.
    static func startNewVaultAlongsideExisting(
        password: String,
        secretStore: any SecretStore
    ) async throws -> VaultBootstrap {
        // createVault already generates a fresh random vaultId + locator,
        // so this is the same operation — the "alongside existing" guarantee
        // comes from the random locator never colliding with an existing
        // bootstrap's locator (UUIDs are unique by construction).
        try await createVault(password: password, secretStore: secretStore)
    }
}

// MARK: - Remember-unlock lifetime (T182/T220, FR-162a clarified 2026-08-07)
//
// The remember-unlock feature stores the unwrapped vault master key in a
// Keychain item (referenced by `rememberedUnlockKeychainRef`) so ordinary
// app relaunches do not re-prompt for the password. The Keychain item MUST
// be cleared on explicit lock. The application MUST NOT behave as a
// login-item-bound daemon that keeps the vault unlocked across system
// logout or restart; after logout/restart the password is required again.
//
// App-launch unlock (FR-162a): at launch with remember enabled, compare the
// stored `rememberedUnlockBootTimestamp` against the current system boot
// timestamp. If they match AND the vault was not explicitly locked, silently
// restore the unlocked state from Keychain. Otherwise prompt for the
// password. The boot-timestamp comparison is the SOLE restart-detection
// mechanism (no login-item/daemon dependency).
//
// Toggle-off while unlocked (FR-162a): toggling `rememberedUnlock` from
// `enabledUntilLockOrRestart` to `disabled` while the vault is currently
// unlocked immediately removes the remembered key from Keychain (clears
// `rememberedUnlockKeychainRef` + `rememberedUnlockBootTimestamp`) but
// preserves the current unlocked vault state in memory until explicit lock
// or app exit. No forced re-prompt.

public extension VaultBootstrapService {

    /// Enables remember-unlock: stores the unwrapped master key in the
    /// Keychain (via the secret store) under a fresh ref, captures the
    /// current boot timestamp, and returns the updated fields.
    ///
    /// - Parameters:
    ///   - vault: The currently-unlocked vault (the key to remember).
    ///   - configuration: The current vault configuration.
    ///   - bootTimestamp: The current system boot timestamp (seconds).
    ///   - secretStore: The Keychain-backed secret store.
    /// - Returns: The new `rememberedUnlockKeychainRef` and
    ///   `rememberedUnlockBootTimestamp` to store on `VaultConfiguration`.
    static func enableRememberUnlock(
        vault: Vault,
        configuration: VaultConfiguration,
        bootTimestamp: Int,
        secretStore: any SecretStore
    ) throws -> (keychainRef: String, bootTimestamp: Int) {
        let ref = "vault-remembered-unlock-\(configuration.vaultId.uuidString)"
        let keyData = vault.masterKey.withUnsafeBytes { Data($0) }
        try secretStore.save(keyData, forKey: ref)
        return (ref, bootTimestamp)
    }

    /// Attempts a silent app-launch unlock when remember-unlock is enabled.
    /// Returns the restored `Vault` if the boot timestamp matches and the
    /// Keychain item is present; returns nil if a password prompt is
    /// required (remember disabled, Mac restarted, vault locked, or
    /// Keychain item missing).
    ///
    /// - Parameters:
    ///   - bootstrap: The vault bootstrap (for suite/version validation).
    ///   - configuration: The locally-configured vault configuration.
    ///   - currentBootTimestamp: The current system boot timestamp.
    ///   - secretStore: The Keychain-backed secret store.
    static func attemptLaunchUnlock(
        bootstrap: VaultBootstrap,
        configuration: VaultConfiguration,
        currentBootTimestamp: Int,
        secretStore: any SecretStore
    ) throws -> Vault? {
        guard configuration.rememberedUnlock == .enabledUntilLockOrRestart else {
            return nil
        }
        guard let storedBoot = configuration.rememberedUnlockBootTimestamp,
              storedBoot == currentBootTimestamp else {
            return nil
        }
        guard let ref = configuration.rememberedUnlockKeychainRef,
              let keyData = try secretStore.load(forKey: ref) else {
            return nil
        }
        guard bootstrap.encryptionSuiteVersion == EncryptionSuite.version,
              bootstrap.formatVersion == VaultBootstrap.currentFormatVersion else {
            return nil
        }
        let masterKey = SymmetricKey(data: keyData)
        return Vault(
            vaultId: bootstrap.vaultId,
            encryptionSuiteVersion: bootstrap.encryptionSuiteVersion,
            masterKey: masterKey
        )
    }

    /// Toggles remember-unlock OFF while the vault is currently unlocked.
    /// Per FR-162a: immediately removes the remembered key from Keychain
    /// (clears the ref + boot timestamp) but preserves the current
    /// unlocked vault state in memory. No forced re-prompt.
    ///
    /// - Returns: The cleared field values (`nil` ref, `nil` timestamp) to
    ///   store on `VaultConfiguration`.
    static func disableRememberUnlock(
        configuration: VaultConfiguration,
        secretStore: any SecretStore
    ) throws {
        if let ref = configuration.rememberedUnlockKeychainRef {
            try secretStore.delete(forKey: ref)
        }
    }

    /// Explicitly locks the vault: clears the remembered-unlock Keychain
    /// item (if any) so future launches prompt for the password.
    static func lockVault(
        configuration: VaultConfiguration,
        secretStore: any SecretStore
    ) throws {
        if let ref = configuration.rememberedUnlockKeychainRef {
            try secretStore.delete(forKey: ref)
        }
    }
}

// MARK: - Repository replacement (T183, FR-154 clarified 2026-08-07)
//
// Replacing an existing sync repository with a new one requires explicit
// user action with a clear warning + confirmation. Upon confirmed
// replacement: local notes are preserved; a new vault bootstraps fresh
// (new vaultId + vaultLocator); the application MUST NOT automatically
// delete the prior repository's remote data (server-side cleanup of the
// old vault remains a manual user responsibility); the prior locator is
// recorded in `VaultConfiguration.replacedFromVaultLocator` for user
// reference. Wrong-vault detection still fires if the new repo already
// contains a different vault.

public extension VaultBootstrapService {

    /// Replaces the current vault with a brand-new vault on a (possibly
    /// different) repository. Local notes are preserved (the caller does
    /// NOT touch the local DB). The prior vault's remote data is NOT
    /// deleted — `priorLocator` is recorded for user reference only.
    ///
    /// - Parameters:
    ///   - password: The password for the NEW vault.
    ///   - priorLocator: The prior vault's locator (recorded on the new
    ///     configuration's `replacedFromVaultLocator` for user reference).
    ///   - secretStore: The Keychain-backed secret store.
    /// - Returns: The new bootstrap + the new configuration shell (caller
    ///   fills in providerType/providerConfig/keychainCredentialRef).
    static func replaceRepository(
        password: String,
        priorLocator: String,
        secretStore: any SecretStore,
        isTestFixture: Bool = false
    ) async throws -> (bootstrap: VaultBootstrap, priorLocator: String) {
        // Start a fresh vault under a fresh random locator. The prior
        // vault's remote data is untouched (no DELETE issued against the
        // old locator — server-side cleanup is a manual user responsibility).
        let newBootstrap = try await createVault(password: password, secretStore: secretStore, isTestFixture: isTestFixture)
        return (newBootstrap, priorLocator)
    }
}

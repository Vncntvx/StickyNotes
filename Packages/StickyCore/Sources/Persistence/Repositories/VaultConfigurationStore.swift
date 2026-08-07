import Foundation
import GRDB
import Domain

// MARK: - VaultConfigurationStore (T285)
//
// Per tasks.md T285 and data-model.md §VaultConfiguration / §SyncState:
// device-local persistence of the sync vault configuration and the per-vault
// sync run state. NEVER synchronized, NEVER in canonical JSON, NEVER in
// exported diagnostics (FR-165/FR-191). Secrets live in Keychain
// (referenced by `VaultConfiguration.keychainCredentialRef`), never here.
//
// The rows back the app's sync-status surface (T284): the menu-bar library
// shows real configuration/state instead of the hardcoded "not configured"
// placeholder.

/// Repository for the device-local `vaultConfiguration` and `syncState` rows.
public final class SQLiteVaultConfigurationStore: Sendable {
    private let store: DatabaseStore
    private let encoder: CanonicalJSONEncoder
    private let decoder: CanonicalJSONDecoder

    public init(store: DatabaseStore) {
        self.store = store
        self.encoder = CanonicalJSONEncoder()
        self.decoder = CanonicalJSONDecoder()
    }

    // MARK: - VaultConfiguration

    /// Fetches the locally-configured vault, or nil when sync is unconfigured.
    public func fetchConfiguration() async throws -> VaultConfiguration? {
        try await store.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM vaultConfiguration LIMIT 1") else {
                return nil
            }
            return try self.decodeConfiguration(row)
        }
    }

    /// Inserts or replaces the local vault configuration (one at a time —
    /// FR-150/FR-154).
    public func saveConfiguration(_ configuration: VaultConfiguration) async throws {
        try await store.write { db in
            let json = try self.encoder.encode(configuration.providerConfig)
            let jsonString = String(data: json, encoding: .utf8) ?? "{}"
            try db.execute(
                sql: """
                    INSERT INTO vaultConfiguration (
                        vaultId, vaultLocator, providerType, providerConfig,
                        keychainCredentialRef, rememberedUnlock, rememberedUnlockKeychainRef,
                        rememberedUnlockBootTimestamp, replacedFromVaultLocator, createdAt
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(vaultId) DO UPDATE SET
                        vaultLocator = excluded.vaultLocator,
                        providerType = excluded.providerType,
                        providerConfig = excluded.providerConfig,
                        keychainCredentialRef = excluded.keychainCredentialRef,
                        rememberedUnlock = excluded.rememberedUnlock,
                        rememberedUnlockKeychainRef = excluded.rememberedUnlockKeychainRef,
                        rememberedUnlockBootTimestamp = excluded.rememberedUnlockBootTimestamp,
                        replacedFromVaultLocator = excluded.replacedFromVaultLocator,
                        createdAt = excluded.createdAt
                    """,
                arguments: [
                    configuration.vaultId.uuidString,
                    configuration.vaultLocator,
                    configuration.providerType.rawValue,
                    jsonString,
                    configuration.keychainCredentialRef,
                    configuration.rememberedUnlock.rawValue,
                    configuration.rememberedUnlockKeychainRef,
                    configuration.rememberedUnlockBootTimestamp,
                    configuration.replacedFromVaultLocator,
                    configuration.createdAt,
                ]
            )
        }
    }

    /// Removes the local configuration WITHOUT deleting local notes or remote
    /// data (FR-151; server-side cleanup is a manual user responsibility).
    public func deleteConfiguration() async throws {
        try await store.write { db in
            try db.execute(sql: "DELETE FROM vaultConfiguration")
        }
    }

    // MARK: - SyncState

    /// Fetches the per-vault sync run state, or nil when never synced.
    public func fetchState() async throws -> SyncState? {
        try await store.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM syncState LIMIT 1") else {
                return nil
            }
            return try self.decodeState(row)
        }
    }

    /// Upserts the per-vault sync run state (last success, sanitized error,
    /// in-progress, redacted config).
    public func upsertState(_ state: SyncState) async throws {
        try await store.write { db in
            let json = try self.encoder.encode(state.config)
            let jsonString = String(data: json, encoding: .utf8) ?? "{}"
            try db.execute(
                sql: """
                    INSERT INTO syncState (
                        vaultId, providerType, lastSuccessfulSyncAt, lastError,
                        inProgress, pendingSince, config
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(vaultId) DO UPDATE SET
                        providerType = excluded.providerType,
                        lastSuccessfulSyncAt = excluded.lastSuccessfulSyncAt,
                        lastError = excluded.lastError,
                        inProgress = excluded.inProgress,
                        pendingSince = excluded.pendingSince,
                        config = excluded.config
                    """,
                arguments: [
                    state.vaultId.uuidString,
                    state.providerType.rawValue,
                    state.lastSuccessfulSyncAt,
                    state.lastError,
                    state.inProgress,
                    state.pendingSince,
                    jsonString,
                ]
            )
        }
    }

    /// Clears the sync run state (e.g. after removing the configuration).
    public func deleteState() async throws {
        try await store.write { db in
            try db.execute(sql: "DELETE FROM syncState")
        }
    }

    // MARK: - Decoding

    private func decodeConfiguration(_ row: Row) throws -> VaultConfiguration {
        // The provider config is stored as a canonical JSON blob; the
        // remaining scalar columns shadow the JSON for stability.
        let providerType = ProviderType(rawValue: row["providerType"] ?? "webdav") ?? .webdav
        let configJSON: String = row["providerConfig"] ?? "{}"
        let providerConfig = try decoder.decode(RedactedSyncConfig.self, from: Data(configJSON.utf8))
        return VaultConfiguration(
            vaultId: UUID(uuidString: row["vaultId"] ?? "") ?? UUID(),
            vaultLocator: row["vaultLocator"] ?? "",
            providerType: providerType,
            providerConfig: providerConfig,
            keychainCredentialRef: row["keychainCredentialRef"] ?? "",
            rememberedUnlock: RememberedUnlock(rawValue: row["rememberedUnlock"] ?? "disabled") ?? .disabled,
            rememberedUnlockKeychainRef: row["rememberedUnlockKeychainRef"],
            rememberedUnlockBootTimestamp: row["rememberedUnlockBootTimestamp"],
            replacedFromVaultLocator: row["replacedFromVaultLocator"],
            createdAt: row["createdAt"]
        )
    }

    private func decodeState(_ row: Row) throws -> SyncState {
        let providerType = ProviderType(rawValue: row["providerType"] ?? "webdav") ?? .webdav
        let configJSON: String = row["config"] ?? "{}"
        let config = try decoder.decode(RedactedSyncConfig.self, from: Data(configJSON.utf8))
        return SyncState(
            vaultId: UUID(uuidString: row["vaultId"] ?? "") ?? UUID(),
            providerType: providerType,
            lastSuccessfulSyncAt: row["lastSuccessfulSyncAt"],
            lastError: row["lastError"],
            inProgress: row["inProgress"] ?? false,
            pendingSince: row["pendingSince"],
            config: config
        )
    }
}

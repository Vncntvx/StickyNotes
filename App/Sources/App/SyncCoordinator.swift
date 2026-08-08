import Foundation
import Observation
import Domain
import Persistence
import SecurityCore
import SyncCore
import AssetStore

// MARK: - SyncCoordinator (T284/T285)
//
// Per tasks.md T284/T285 and spec FR-150/FR-151/FR-152/FR-152a/FR-154/
// FR-162/FR-162a/FR-163:
//
// The app-side synchronization composition root:
// - Persists the device-local `VaultConfiguration` + `SyncState` via
//   SQLiteVaultConfigurationStore (never synced; secrets in Keychain).
// - Creates/opens the vault (VaultBootstrapService, FR-160c minimums),
//   builds the WebDAV/S3 provider from Keychain-held credentials, and wires
//   the SyncEngine (T117) with the SyncConflictResolver (T171).
// - Drives FR-152 triggers: manual sync (FR-151), a 2-4 s debounce after
//   local changes (FR-152a, SyncDebouncer), and startup sync when the vault
//   is remembered (FR-162a launch unlock).
// - Exposes sanitized status (last success, error code, in-progress) for the
//   menu-bar library (T284) and the Settings surface (T170/T285).
// - Repository replacement (FR-154): fresh vault, prior remote data never
//   auto-deleted; remember-unlock toggle (FR-162a) with boot-timestamp
//   restart detection.
//
// Tests inject an in-memory provider via `providerOverride` so the whole
// configure → sync → status path is exercised without network.

/// Credentials for the configured provider (device-local; Keychain-held).
public struct SyncProviderCredentials: Sendable, Codable, Equatable {
    public var username: String?
    public var password: String?
    public var accessKey: String?
    public var secretKey: String?

    public init(username: String? = nil, password: String? = nil, accessKey: String? = nil, secretKey: String? = nil) {
        self.username = username
        self.password = password
        self.accessKey = accessKey
        self.secretKey = secretKey
    }
}

@MainActor
@Observable
public final class SyncCoordinator {
    public private(set) var configuration: VaultConfiguration?
    public private(set) var lastSuccessfulSyncAt: Date?
    public private(set) var lastErrorCode: String?
    public private(set) var isInProgress = false
    public private(set) var autoSyncEnabled = false

    private let store: DatabaseStore
    private let configStore: SQLiteVaultConfigurationStore
    private let secretStore: any SecretStore
    private let deviceId: UUID
    /// The composed asset store (T293): assets sync as independent encrypted
    /// objects (FR-090a) — passed into every SyncEngine instance.
    private let assetStore: AssetStore?
    private var engine: SyncEngine?
    private var debouncer: SyncDebouncer?
    /// The unlocked vault (FR-162a remember-unlock needs the master key).
    private var vault: Vault?
    /// Test seam: replaces the real provider construction.
    private let providerOverride: (@Sendable (VaultConfiguration, SyncProviderCredentials) -> any SyncProviderProtocol)?

    public init(
        store: DatabaseStore,
        secretStore: any SecretStore,
        deviceId: UUID,
        assetStore: AssetStore? = nil,
        providerOverride: (@Sendable (VaultConfiguration, SyncProviderCredentials) -> any SyncProviderProtocol)? = nil
    ) {
        self.store = store
        self.configStore = SQLiteVaultConfigurationStore(store: store)
        self.secretStore = secretStore
        self.deviceId = deviceId
        self.assetStore = assetStore
        self.providerOverride = providerOverride
    }

    // MARK: - Status (T284)

    public var isConfigured: Bool { configuration != nil }

    /// Loads the persisted configuration + state (app launch).
    public func load() async {
        if let config = try? await configStore.fetchConfiguration() {
            self.configuration = config
            if let state = try? await configStore.fetchState() {
                self.lastSuccessfulSyncAt = state.lastSuccessfulSyncAt
                self.lastErrorCode = state.lastError
            }
            autoSyncEnabled = LocalPreferences().autoSyncEnabled
            // FR-162a: silent launch unlock when remembered + no restart.
            if let vault = launchUnlockVault(configuration: config) {
                wireEngine(configuration: config, vault: vault)
            }
        }
    }

    /// FR-162a: silently restores the unlocked vault when "remember" is
    /// enabled and the Mac has not restarted since (boot-timestamp compare).
    private func launchUnlockVault(configuration: VaultConfiguration) -> Vault? {
        let boot = Int(Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime)
        return try? VaultBootstrapService.attemptLaunchUnlock(
            bootstrap: VaultBootstrap(
                vaultId: configuration.vaultId,
                vaultLocator: configuration.vaultLocator,
                argon2id: Argon2Parameters.recommended,
                wrappedMasterKey: .init(nonce: Data(), sealed: Data()),
                keyConfirmation: nil
            ),
            configuration: configuration,
            currentBootTimestamp: boot,
            secretStore: secretStore
        )
    }

    // MARK: - Configure (FR-150/FR-151)

    /// Configures a new vault + repository. Fail-closed: any error leaves
    /// the previous configuration untouched (no partial state).
    public func configure(
        providerType: ProviderType,
        endpoint: String,
        containerPath: String?,
        bucket: String?,
        region: String?,
        credentials: SyncProviderCredentials,
        vaultPassword: String,
        rememberUnlock: Bool,
        isTestFixture: Bool = false
    ) async throws {
        // 1. Vault creation (FR-160c production minimums unless test fixture).
        let bootstrap = try await VaultBootstrapService.createVault(
            password: vaultPassword,
            secretStore: secretStore,
            isTestFixture: isTestFixture
        )
        let key = try await VaultBootstrapService.openVault(bootstrap, password: vaultPassword)
        let vault = Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: bootstrap.encryptionSuiteVersion, masterKey: key)

        // 2. Persist Keychain credentials (never in SQLite/UserDefaults).
        let credentialsKey = "vault-provider-credentials-\(bootstrap.vaultId.uuidString)"
        let credentialsData = try CanonicalJSONEncoder().encode(credentials)
        try secretStore.save(credentialsData, forKey: credentialsKey)

        // 3. Build the provider + verify connectivity.
        let redacted = redactedConfig(providerType: providerType, endpoint: endpoint, bucket: bucket, region: region, containerPath: containerPath)
        let configuration = VaultConfiguration(
            vaultId: bootstrap.vaultId,
            vaultLocator: bootstrap.vaultLocator,
            providerType: providerType,
            providerConfig: redacted,
            keychainCredentialRef: credentialsKey,
            rememberedUnlock: rememberUnlock ? .enabledUntilLockOrRestart : .disabled
        )
        let provider = try makeProvider(configuration: configuration, credentials: credentials)
        try await provider.verify()

        // 4. Persist the configuration (device-local; one at a time).
        try await configStore.saveConfiguration(configuration)

        // 5. Wire the engine + debouncer and run the initial sync.
        self.configuration = configuration
        self.vault = vault
        self.lastErrorCode = nil
        wireEngine(configuration: configuration, vault: vault)
        await runSync()

        // FR-162a: remember-unlock stores the key + boot timestamp.
        if rememberUnlock {
            await setRememberUnlockInternal(enabled: true, configuration: configuration, vault: vault)
        }
    }

    /// Tests connectivity + credentials without configuring (FR-151).
    public func testConnection(
        providerType: ProviderType,
        endpoint: String,
        containerPath: String?,
        bucket: String?,
        region: String?,
        credentials: SyncProviderCredentials
    ) async throws {
        let redacted = redactedConfig(providerType: providerType, endpoint: endpoint, bucket: bucket, region: region, containerPath: containerPath)
        let configuration = VaultConfiguration(
            vaultId: UUID(),
            vaultLocator: RemoteLayout.opaqueObjectName(),
            providerType: providerType,
            providerConfig: redacted,
            keychainCredentialRef: ""
        )
        let provider = try makeProvider(configuration: configuration, credentials: credentials)
        try await provider.verify()
    }

    // MARK: - Sync (FR-151/FR-152/FR-152a)

    /// Manual sync (FR-151) with explicit non-blocking status (FR-141b).
    public func manualSync() async {
        guard engine != nil, !isInProgress else { return }
        await debouncer?.cancel()
        await runSync()
    }

    /// FR-152a: 2-4 s debounce after local changes (cancelable by manual
    /// sync / shutdown / network change). Call from every persistence write.
    public func localContentChanged() async {
        guard autoSyncEnabled else { return }
        await debouncer?.localContentChanged()
    }

    public func setAutoSyncEnabled(_ enabled: Bool) {
        autoSyncEnabled = enabled
        LocalPreferences().autoSyncEnabled = enabled
    }

    // MARK: - Remove / replace (FR-151/FR-154)

    /// Removes the local configuration WITHOUT deleting local notes or
    /// remote data (FR-151; server-side cleanup is manual).
    public func removeConfiguration() async {
        guard let configuration else { return }
        try? await configStore.deleteConfiguration()
        try? await configStore.deleteState()
        try? secretStore.delete(forKey: configuration.keychainCredentialRef)
        if let ref = configuration.rememberedUnlockKeychainRef {
            try? secretStore.delete(forKey: ref)
        }
        engine = nil
        debouncer = nil
        self.configuration = nil
        lastSuccessfulSyncAt = nil
        lastErrorCode = nil
    }

    /// FR-154: replaces the repository with a fresh vault. Local notes are
    /// preserved; prior remote data is NOT deleted (manual responsibility).
    public func replaceRepository(
        providerType: ProviderType,
        endpoint: String,
        containerPath: String?,
        bucket: String?,
        region: String?,
        credentials: SyncProviderCredentials,
        vaultPassword: String,
        isTestFixture: Bool = false
    ) async throws {
        guard let prior = configuration else {
            throw StickyError.credentials(.notConfigured)
        }
        let result = try await VaultBootstrapService.replaceRepository(
            password: vaultPassword,
            priorLocator: prior.vaultLocator,
            secretStore: secretStore,
            isTestFixture: isTestFixture
        )
        let key = try await VaultBootstrapService.openVault(result.bootstrap, password: vaultPassword)
        let vault = Vault(vaultId: result.bootstrap.vaultId, encryptionSuiteVersion: result.bootstrap.encryptionSuiteVersion, masterKey: key)

        let credentialsKey = "vault-provider-credentials-\(result.bootstrap.vaultId.uuidString)"
        let credentialsData = try CanonicalJSONEncoder().encode(credentials)
        try secretStore.save(credentialsData, forKey: credentialsKey)

        let redacted = redactedConfig(providerType: providerType, endpoint: endpoint, bucket: bucket, region: region, containerPath: containerPath)
        let newConfiguration = VaultConfiguration(
            vaultId: result.bootstrap.vaultId,
            vaultLocator: result.bootstrap.vaultLocator,
            providerType: providerType,
            providerConfig: redacted,
            keychainCredentialRef: credentialsKey,
            rememberedUnlock: .disabled,
            replacedFromVaultLocator: prior.vaultLocator
        )
        let provider = try makeProvider(configuration: newConfiguration, credentials: credentials)
        try await provider.verify()
        try await configStore.saveConfiguration(newConfiguration)

        self.configuration = newConfiguration
        self.vault = vault
        lastErrorCode = nil
        wireEngine(configuration: newConfiguration, vault: vault)
        await runSync()
    }

    // MARK: - Remember-unlock (FR-162a)

    public func setRememberUnlock(_ enabled: Bool) async throws {
        guard let configuration, let vault else { return }
        if enabled {
            // The engine holds the unlocked vault; remember its key.
            let boot = Int(Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime)
            let (ref, timestamp) = try VaultBootstrapService.enableRememberUnlock(
                vault: vault,
                configuration: configuration,
                bootTimestamp: boot,
                secretStore: secretStore
            )
            var updated = configuration
            updated.rememberedUnlock = .enabledUntilLockOrRestart
            updated.rememberedUnlockKeychainRef = ref
            updated.rememberedUnlockBootTimestamp = timestamp
            try await configStore.saveConfiguration(updated)
            self.configuration = updated
        } else {
            try VaultBootstrapService.disableRememberUnlock(configuration: configuration, secretStore: secretStore)
            var updated = configuration
            updated.rememberedUnlock = .disabled
            updated.rememberedUnlockKeychainRef = nil
            updated.rememberedUnlockBootTimestamp = nil
            try await configStore.saveConfiguration(updated)
            self.configuration = updated
        }
    }

    // MARK: - Internals

    private func redactedConfig(
        providerType: ProviderType,
        endpoint: String,
        bucket: String?,
        region: String?,
        containerPath: String?
    ) -> RedactedSyncConfig {
        switch providerType {
        case .webdav:
            return RedactedSyncConfig(endpoint: endpoint, region: nil, bucket: nil, prefix: containerPath)
        case .s3:
            return RedactedSyncConfig(endpoint: endpoint, region: region, bucket: bucket, prefix: nil)
        }
    }

    /// Builds the provider: test override or the real adapter (credentials
    /// resolved from the Keychain by the caller).
    private func makeProvider(
        configuration: VaultConfiguration,
        credentials: SyncProviderCredentials
    ) throws -> any SyncProviderProtocol {
        if let providerOverride {
            return providerOverride(configuration, credentials)
        }
        switch configuration.providerType {
        case .webdav:
            guard let url = URL(string: configuration.providerConfig.endpoint) else {
                throw StickyError.credentials(.invalidEndpoint)
            }
            return WebDAVProvider(config: WebDAVConfiguration(
                baseURL: url,
                containerPath: configuration.providerConfig.prefix ?? "",
                username: credentials.username,
                password: credentials.password
            ))
        case .s3:
            guard let url = URL(string: configuration.providerConfig.endpoint),
                  let bucket = configuration.providerConfig.bucket else {
                throw StickyError.credentials(.invalidEndpoint)
            }
            return S3Provider(config: S3Configuration(
                endpoint: url,
                region: configuration.providerConfig.region ?? "us-east-1",
                bucket: bucket,
                prefix: configuration.vaultLocator,
                accessKey: credentials.accessKey ?? "",
                secretKey: credentials.secretKey ?? ""
            ))
        }
    }

    private func wireEngine(configuration: VaultConfiguration, vault: Vault) {
        do {
            let credentialsData = try secretStore.load(forKey: configuration.keychainCredentialRef)
            let credentials = credentialsData.flatMap { try? CanonicalJSONDecoder().decode(SyncProviderCredentials.self, from: $0) }
                ?? SyncProviderCredentials()
            let provider = try makeProvider(configuration: configuration, credentials: credentials)
            let engine = SyncEngine(
                provider: provider,
                vault: vault,
                store: store,
                deviceId: deviceId,
                conflictResolver: SyncConflictResolver(store: store),
                assetStore: assetStore
            )
            self.engine = engine
            self.debouncer = SyncDebouncer(engine: engine)
        } catch {
            self.engine = nil
            self.debouncer = nil
            lastErrorCode = StickyError.credentials(.accessDenied).sanitizedCode
        }
    }

    /// Runs one sync pass and records the sanitized outcome (FR-165).
    private func runSync() async {
        guard let engine else { return }
        isInProgress = true
        defer { isInProgress = false }
        do {
            let summary = try await engine.syncNow()
            lastSuccessfulSyncAt = Date()
            lastErrorCode = nil
            try? await configStore.upsertState(SyncState(
                vaultId: configuration?.vaultId ?? UUID(),
                providerType: configuration?.providerType ?? .webdav,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                lastError: nil,
                inProgress: false,
                config: configuration?.providerConfig ?? RedactedSyncConfig(endpoint: "unconfigured")
            ))
            // FR-174-d: inform the user that sync history has aged out.
            if summary.historyAgedOutDetected {
                lastErrorCode = "sync.historyAgedOut"
            }
            // T302 (FR-110a): new conflict copies affect the widget surface —
            // reload exactly the conflict-copy kinds.
            if summary.conflictCopiesCreated > 0 {
                WidgetRefreshCoordinator.reload(for: .conflictCopyCreated)
            }
        } catch {
            // FR-165: sanitized codes only. Map every error family — a
            // non-StickyError (e.g. ProviderError or a raw URLSession error
            // that escaped the provider adapter) previously collapsed to the
            // uninformative "syncFailed" fallback.
            let code: String
            if let sticky = error as? StickyError {
                code = sticky.sanitizedCode
            } else if let provider = error as? ProviderError {
                code = "provider.\(provider.sanitizedCode)"
            } else {
                let ns = error as NSError
                code = "syncFailed.\(ns.domain).\(ns.code)"
            }
            lastErrorCode = code
            try? await configStore.upsertState(SyncState(
                vaultId: configuration?.vaultId ?? UUID(),
                providerType: configuration?.providerType ?? .webdav,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                lastError: code,
                inProgress: false,
                config: configuration?.providerConfig ?? RedactedSyncConfig(endpoint: "unconfigured")
            ))
        }
    }

    private func setRememberUnlockInternal(enabled: Bool, configuration: VaultConfiguration, vault: Vault) async {
        if enabled {
            let boot = Int(Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime)
            guard let rememberResult = try? VaultBootstrapService.enableRememberUnlock(
                vault: vault,
                configuration: configuration,
                bootTimestamp: boot,
                secretStore: secretStore
            ) else { return }
            let (ref, timestamp) = rememberResult
            var updated = configuration
            updated.rememberedUnlock = .enabledUntilLockOrRestart
            updated.rememberedUnlockKeychainRef = ref
            updated.rememberedUnlockBootTimestamp = timestamp
            self.configuration = updated
            try? await configStore.saveConfiguration(updated)
        }
    }
}

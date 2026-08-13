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

/// A vault discovered on a configured repository (scan-before-join).
public struct DiscoveredVault: Sendable, Equatable, Identifiable {
    /// The vault's stable identity (from its bootstrap — read-only, no
    /// password needed to enumerate vaults).
    public let vaultId: UUID
    /// The opaque remote locator — what the join flow needs.
    public let vaultLocator: String
    /// When the vault was created (bootstrap `createdAt`).
    public let createdAt: Date

    public var id: UUID { vaultId }

    public init(vaultId: UUID, vaultLocator: String, createdAt: Date) {
        self.vaultId = vaultId
        self.vaultLocator = vaultLocator
        self.createdAt = createdAt
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
    /// The user-selected automatic-sync strategy (FR-152, clarified
    /// 2026-08-08): change-only or a fixed periodic interval.
    public private(set) var autoSyncPolicy: AutoSyncPolicy = .default

    private let store: DatabaseStore
    private let configStore: SQLiteVaultConfigurationStore
    private let secretStore: any SecretStore
    private let deviceId: UUID
    /// The composed asset store (T293): assets sync as independent encrypted
    /// objects (FR-090a) — passed into every SyncEngine instance.
    private let assetStore: AssetStore?
    private var engine: SyncEngine?
    private var debouncer: SyncDebouncer?
    /// The periodic-sync task (FR-152 periodic strategy; changeOnly stops it).
    private var periodicTask: Task<Void, Never>?
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

    /// The configured vault's encryption-suite version (nil when no vault is
    /// unlocked/configured). Used by the sync-profile export (T032/FR-009)
    /// so the file always reflects the actual vault, never a hardcoded value.
    public var encryptionSuiteVersion: Int? {
        vault?.encryptionSuiteVersion
    }

    /// Loads the persisted configuration + state (app launch).
    public func load() async {
        if let config = try? await configStore.fetchConfiguration() {
            self.configuration = config
            if let state = try? await configStore.fetchState() {
                self.lastSuccessfulSyncAt = state.lastSuccessfulSyncAt
                self.lastErrorCode = state.lastError
            }
            autoSyncEnabled = LocalPreferences().autoSyncEnabled
            autoSyncPolicy = LocalPreferences().autoSyncPolicy
            // FR-162a: silent launch unlock when remembered + no restart.
            if let vault = launchUnlockVault(configuration: config) {
                wireEngine(configuration: config, vault: vault)
            }
        }
    }

    /// FR-162a: silently restores the unlocked vault when "remember" is
    /// enabled and the Mac has not restarted since (boot-timestamp compare).
    private func launchUnlockVault(configuration: VaultConfiguration) -> Vault? {
        return try? VaultBootstrapService.attemptLaunchUnlock(
            bootstrap: VaultBootstrap(
                vaultId: configuration.vaultId,
                vaultLocator: configuration.vaultLocator,
                argon2id: Argon2Parameters.recommended,
                wrappedMasterKey: .init(nonce: Data(), sealed: Data()),
                keyConfirmation: nil
            ),
            configuration: configuration,
            currentBootTimestamp: SystemBootTime.current(),
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

        // 3b. Upload the bootstrap object (T026, plan §Bootstrap object
        // name): the join path fetches it under the SAME deterministic name.
        // Fail closed — any error leaves the local config unwritten.
        try await provider.upload(
            objectName: RemoteLayout.bootstrapObjectName(for: bootstrap.vaultLocator),
            data: try bootstrap.canonicalJSON()
        )

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

    /// Scans the configured repository (user prefix level, READ-ONLY) for
    /// existing vaults and returns them without needing any vault password:
    /// each vault's bootstrap is listed + fetched by its derived object
    /// name, so the user can PICK a vault to join instead of typing the
    /// locator. Returns vaults sorted by creation date.
    ///
    /// - Throws: provider connectivity/authorization errors; a repository
    ///   with zero vaults returns an empty array (not an error).
    public func discoverVaults(
        providerType: ProviderType,
        endpoint: String,
        containerPath: String?,
        bucket: String?,
        region: String?,
        credentials: SyncProviderCredentials
    ) async throws -> [DiscoveredVault] {
        // 1. Repository-level provider (user prefix only, NO vault locator).
        let redacted = redactedConfig(providerType: providerType, endpoint: endpoint, bucket: bucket, region: region, containerPath: containerPath)
        let repoConfiguration = VaultConfiguration(
            vaultId: UUID(),
            vaultLocator: "",
            providerType: providerType,
            providerConfig: redacted,
            keychainCredentialRef: ""
        )
        let repoProvider = try makeProvider(configuration: repoConfiguration, credentials: credentials)

        // 2. List everything under the user prefix. Each vault lives in its
        //    own "<locator>/" subdirectory; the manifest + bootstrap objects
        //    live inside it. Derive candidate locators from the first path
        //    segment.
        let objects = try await repoProvider.list()
        var locators = Set<String>()
        for metadata in objects {
            let first = metadata.objectName.split(separator: "/").first.map(String.init) ?? metadata.objectName
            if !first.isEmpty, first != ManifestStore.manifestObjectName {
                locators.insert(first)
            }
        }

        // 3. For each candidate locator, fetch the bootstrap (READ-ONLY) and
        //    keep only those that parse as real vaults.
        var vaults: [DiscoveredVault] = []
        for locator in locators {
            let config = VaultConfiguration(
                vaultId: UUID(),
                vaultLocator: locator,
                providerType: providerType,
                providerConfig: redacted,
                keychainCredentialRef: ""
            )
            let provider = try makeProvider(configuration: config, credentials: credentials)
            guard let data = try? await provider.fetch(
                objectName: RemoteLayout.bootstrapObjectName(for: locator)
            ), let bootstrap = try? VaultBootstrap.fromCanonicalJSON(data) else {
                continue  // not a vault (or unreadable) — skip
            }
            vaults.append(DiscoveredVault(
                vaultId: bootstrap.vaultId,
                vaultLocator: locator,
                createdAt: bootstrap.createdAt
            ))
        }
        return vaults.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Join existing vault (T011/T012, US1)

    /// Joins a vault created on another device (FR-002/FR-003): READ-ONLY
    /// probe + fetch of the remote bootstrap by locator → verify (wrong
    /// password / wrong vault fail closed, distinguishable) → persist the
    /// single configuration (replace semantics, FR-154) → wire the engine →
    /// immediate sync. Network + crypto are off the main actor (FR-012).
    /// Failure leaves NO local config row and NO remote mutation (FR-004/
    /// FR-005, CHK030/CHK035).
    public func joinExistingVault(
        providerType: ProviderType,
        endpoint: String,
        containerPath: String?,
        bucket: String?,
        region: String?,
        vaultLocator: String,
        credentials: SyncProviderCredentials,
        vaultPassword: String,
        expectedVaultId: UUID? = nil
    ) async throws {
        // 1. Build the provider + READ-ONLY connectivity probe (FR-003:
        //    join MUST NOT create any remote object — no MKCOL; a HEAD /
        //    fetchMetadata on the manifest name is enough).
        let redacted = redactedConfig(providerType: providerType, endpoint: endpoint, bucket: bucket, region: region, containerPath: containerPath)
        let configuration = VaultConfiguration(
            vaultId: UUID(),
            vaultLocator: vaultLocator,
            providerType: providerType,
            providerConfig: redacted,
            keychainCredentialRef: ""
        )
        let provider = try makeProvider(configuration: configuration, credentials: credentials)
        _ = try await provider.fetchMetadata(objectName: ManifestStore.manifestObjectName)

        // 2. Fetch the remote bootstrap by locator (READ-ONLY, FR-003).
        let bootstrapName = RemoteLayout.bootstrapObjectName(for: vaultLocator)
        let wire: Data
        do {
            wire = try await provider.fetch(objectName: bootstrapName)
        } catch ProviderError.notFound {
            throw StickyError.credentials(.notFound)
        }

        // 3. Verify: wrong password fails closed with a distinguishable
        //    code (FR-004/CHK028). `expectedVaultId` is ONLY the user's
        //    stated expectation (e.g. from an imported sync profile —
        //    CHK025: joining a location whose bootstrap is a DIFFERENT vault
        //    than the imported profile's fails closed). The locally RETAINED
        //    configuration is deliberately NOT the expected identity: joining
        //    a different vault than the retained one is the replace
        //    semantics of US1/AC6/FR-007 (the prior locator is recorded on
        //    the new configuration for the user's reference).
        let retained = try? await configStore.fetchConfiguration()
        let key = try await VaultBootstrapService.openRemoteBootstrap(
            remoteBootstrap: wire,
            password: vaultPassword,
            expectedVaultId: expectedVaultId
        )
        let parsedBootstrap = try VaultBootstrap.fromCanonicalJSON(wire)
        let vault = Vault(
            vaultId: parsedBootstrap.vaultId,
            encryptionSuiteVersion: parsedBootstrap.encryptionSuiteVersion,
            masterKey: key
        )

        // 4. Persist the configuration (single-row replace, FR-154); the
        //    remote bootstrap is never modified.
        let credentialsKey = "vault-provider-credentials-\(vault.vaultId.uuidString)"
        let credentialsData = try CanonicalJSONEncoder().encode(credentials)
        try secretStore.save(credentialsData, forKey: credentialsKey)
        let joined = VaultConfiguration(
            vaultId: vault.vaultId,
            vaultLocator: vaultLocator,
            providerType: providerType,
            providerConfig: redacted,
            keychainCredentialRef: credentialsKey,
            rememberedUnlock: .disabled,
            replacedFromVaultLocator: retained?.vaultLocator
        )
        try await configStore.saveConfiguration(joined)

        // 5. Wire the engine + immediate sync (FR-006): local notes upload
        //    encrypted via the existing engine path.
        self.configuration = joined
        self.vault = vault
        self.lastErrorCode = nil
        wireEngine(configuration: joined, vault: vault)
        await runSync()
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
        if enabled {
            startPeriodicSync()
        } else {
            stopPeriodicSync()
        }
    }

    /// Selects the automatic-sync strategy (FR-152, clarified 2026-08-08):
    /// persists the device-local preference and restarts the periodic timer
    /// (a `changeOnly` policy stops it; the FR-152a change debounce always
    /// applies when auto-sync is enabled).
    public func setAutoSyncPolicy(_ policy: AutoSyncPolicy) {
        autoSyncPolicy = policy
        LocalPreferences().autoSyncPolicy = policy
        if autoSyncEnabled {
            startPeriodicSync()
        }
    }

    // MARK: - Periodic sync (FR-152 periodic strategy, clarified 2026-08-08)

    /// Starts (or restarts) the periodic-sync task per the selected policy.
    /// `changeOnly` or a disabled auto-sync stops it. The loop sleeps for the
    /// policy interval and runs one sync pass; overlapping runs are excluded
    /// by the engine's single-transaction actor.
    private func startPeriodicSync() {
        stopPeriodicSync()
        guard autoSyncEnabled, let interval = autoSyncPolicy.interval else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                guard let self, self.engine != nil, self.autoSyncEnabled else { return }
                await self.runSync()
            }
        }
    }

    private func stopPeriodicSync() {
        periodicTask?.cancel()
        periodicTask = nil
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
        stopPeriodicSync()
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

        // FR-154: switch atomically — stop the OLD provider's debounce and
        // periodic tasks BEFORE wiring the new engine, so both providers are
        // never active at the same time (any in-flight old-engine request
        // still completes; nothing new is scheduled on it).
        await debouncer?.cancel()
        stopPeriodicSync()

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
            let (ref, timestamp) = try VaultBootstrapService.enableRememberUnlock(
                vault: vault,
                configuration: configuration,
                bootTimestamp: SystemBootTime.current(),
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
            // The optional user folder/prefix is persisted here and combined
            // with the vault locator by makeProvider.
            return RedactedSyncConfig(endpoint: endpoint, region: region, bucket: bucket, prefix: containerPath)
        }
    }

    /// Locator-based remote addressing (T026/T027, plan §Bootstrap object
    /// name): the vault locator is part of the remote container on BOTH
    /// providers (`"<prefix>/<locator>"`, or `"<locator>"` when no user
    /// prefix) so a join by locator reaches the same remote location and
    /// vaults on one repository stay isolated. Pure + testable.
    ///
    /// An EMPTY `vaultLocator` returns the bare user prefix (repository-level
    /// addressing) — used by vault discovery to LIST the whole repository.
    static func remoteContainerPath(prefix: String?, vaultLocator: String) -> String {
        let base = (prefix ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let locator = vaultLocator.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if locator.isEmpty { return base }
        return base.isEmpty ? locator : "\(base)/\(locator)"
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
            // WebDAV locator addressing (T026, plan §Bootstrap object name):
            // the container path includes the vault locator — mirroring the
            // S3 scheme — so a join by locator reaches the same remote
            // location on both providers and vaults stay isolated.
            let containerPath = Self.remoteContainerPath(
                prefix: configuration.providerConfig.prefix,
                vaultLocator: configuration.vaultLocator
            )
            return WebDAVProvider(config: WebDAVConfiguration(
                baseURL: url,
                containerPath: containerPath,
                username: credentials.username,
                password: credentials.password
            ))
        case .s3:
            guard let url = URL(string: configuration.providerConfig.endpoint),
                  let bucket = configuration.providerConfig.bucket else {
                throw StickyError.credentials(.invalidEndpoint)
            }
            // The user-configured folder/prefix (optional) is combined with
            // the vault locator so multiple vaults stay isolated under the
            // chosen prefix (e.g. "mynotes/451aa6fbf…/").
            let prefix = Self.remoteContainerPath(
                prefix: configuration.providerConfig.prefix,
                vaultLocator: configuration.vaultLocator
            )
            return S3Provider(config: S3Configuration(
                endpoint: url,
                region: configuration.providerConfig.region ?? "us-east-1",
                bucket: bucket,
                prefix: prefix,
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
            // FR-152 periodic strategy: start the timer when auto-sync is on.
            startPeriodicSync()
        } catch {
            self.engine = nil
            self.debouncer = nil
            stopPeriodicSync()
            lastErrorCode = StickyError.credentials(.accessDenied).sanitizedCode
        }
    }

    /// Runs one sync pass and records the sanitized outcome (FR-165).
    /// Mutual exclusion: manual / periodic / debounced / startup triggers all
    /// funnel here; a pass already in progress is skipped so triggers can
    /// never queue duplicate syncs (the engine actor additionally serializes
    /// `syncNow`).
    private func runSync() async {
        guard let engine else { return }
        guard !isInProgress else { return }
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
            guard let rememberResult = try? VaultBootstrapService.enableRememberUnlock(
                vault: vault,
                configuration: configuration,
                bootTimestamp: SystemBootTime.current(),
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

/// Real system boot time via `sysctl kern.boottime` (FR-162a).
///
/// The previous formula (`Date() - ProcessInfo.processInfo.systemUptime`)
/// DRIFTED whenever the Mac slept: `systemUptime` excludes sleep time while
/// the wall clock keeps advancing, so the "computed boot time" grew by the
/// accumulated sleep duration. The remember-unlock boot-timestamp compare
/// then saw a "restart" on every launch after any sleep and re-prompted for
/// the password. `kern.boottime` is the REAL boot time — stable across
/// sleep/wake, changed only by an actual reboot.
enum SystemBootTime {
    static func current() -> Int {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else {
            // Fallback: the old formula (still wrong after sleep, but only
            // used when sysctl is unavailable, which never happens on macOS).
            return Int(Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime)
        }
        return Int(boot.tv_sec)
    }
}

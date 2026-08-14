import Foundation
import Domain
import Persistence
import EditorCore
import AssetStore
import SecurityCore
import SyncCore
import SystemBridge

// MARK: - AppEnvironment (T024)
//
// A small composition root with explicit-initializer DI. No DI framework
// (constitution XIII; plan §State management and concurrency). The
// environment is constructed at app startup with concrete service instances
// and passed down to scenes via SwiftUI `@Environment`.
//
// Services are composed, not globally singletoned. Each service is an actor
// or a value type returning `Sendable` snapshots; the environment itself is
// a `Sendable` value carrying references to the long-lived services.

/// The composed application services. Constructed at app startup; passed to
/// scenes via SwiftUI `@Environment` (or `@State` at the app root).
///
/// Placeholder used before bootstrap completes — the menu shows "setup in
/// progress" until `bootstrap` swaps in the real environment, and the
/// Settings scene reads the real `syncCoordinator`/`typography` only after
/// that (R3.8, remediation roadmap 2026-08-14: the "foundation bring-up"
/// framing was stale — Phases 2/3 landed).
public struct AppEnvironment: Sendable {
    public let domain: DomainServices
    public let persistence: PersistenceServices
    public let editor: EditorServices
    public let assets: AssetServices
    public let security: SecurityServices
    public let sync: SyncServices
    public let systemBridge: SystemBridgeServices
    /// Device-local first-launch preferences (FR-014a, T207). Stored in App
    /// Group UserDefaults; never synchronized, never in canonical JSON, never
    /// in exported diagnostics.
    public let localPreferences: LocalPreferences
    /// The sync composition root (T284/T285): vault configuration store +
    /// SyncEngine wiring + status. Nil before bootstrap. Main-actor-isolated
    /// (Sendable by global-actor isolation).
    public let syncCoordinator: SyncCoordinator?
    /// The SINGLE global typography preference source (Phase 2, 2026-08-14):
    /// font family + text spacing, shared by Settings and every note window.
    /// Non-optional — bootstrap always injects the persisted instance; the
    /// default value is a test convenience only (production never relies on
    /// it — see TypographyPreferences).
    public let typography: TypographyPreferences

    public init(
        domain: DomainServices,
        persistence: PersistenceServices,
        editor: EditorServices,
        assets: AssetServices,
        security: SecurityServices,
        sync: SyncServices,
        systemBridge: SystemBridgeServices,
        localPreferences: LocalPreferences,
        syncCoordinator: SyncCoordinator? = nil,
        typography: TypographyPreferences = TypographyPreferences()
    ) {
        self.domain = domain
        self.persistence = persistence
        self.editor = editor
        self.assets = assets
        self.security = security
        self.sync = sync
        self.systemBridge = systemBridge
        self.localPreferences = localPreferences
        self.syncCoordinator = syncCoordinator
        self.typography = typography
    }

    /// Placeholder used during foundation bring-up. Real composition
    /// replaces this once the foundational services exist.
    public static let placeholder = AppEnvironment(
        domain: DomainServices.placeholder,
        persistence: PersistenceServices.placeholder,
        editor: EditorServices.placeholder,
        assets: AssetServices.placeholder,
        security: SecurityServices.placeholder,
        sync: SyncServices.placeholder,
        systemBridge: SystemBridgeServices.placeholder,
        localPreferences: LocalPreferences()
    )

    /// Bootstraps the database and composes the environment (T154).
    ///
    /// Startup sequence per plan §Local storage:
    /// 1. Open the `DatabasePool` (WAL, foreign keys, bounded busy timeout).
    /// 2. Apply the single current schema (no migration chain — see
    ///    Schema.swift; on a fresh database it creates everything, on an
    ///    existing one it is a no-op).
    ///
    /// The app calls this once at launch; a failure refuses to start rather
    /// than running against an inconsistent database (constitution IV, X).
    ///
    /// FR-014a (clarified 2026-08-07) / T210: the startup path performs NO
    /// permission request. `PermissionService.screenRecordingStatus()` uses
    /// `CGPreflightScreenCaptureAccess()` (no prompt); `accessibilityStatus()`
    /// uses `AXIsProcessTrusted()` (no prompt). The actual screen-recording
    /// prompt (`CGRequestWindowCaptureAccess`) is invoked ONLY on capture
    /// invocation (WindowCapture/RegionCapture), never at launch. This
    /// invariant is enforced by audit: the bootstrap path below calls no
    /// `CGRequest*` / `AXIsProcessTrustedWithOptions` API.
    @MainActor
    public static func bootstrap(
        applicationSupportURL: URL
    ) async throws -> AppEnvironment {
        let fm = FileManager.default
        let baseURL = applicationSupportURL
        try fm.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let databasePath = baseURL
            .appendingPathComponent(DatabaseBootstrap.databaseFileName).path

        let store = try await DatabaseBootstrap.open(databasePath: databasePath)

        // T293: compose the asset store under the sandbox Application
        // Support directory (originals/thumbnails/app-icons; never in
        // SQLite).
        let assetDirectory = baseURL.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
        let assetStore = try AssetStore(directoryURL: assetDirectory)
        // R1.1 (remediation roadmap 2026-08-14): relaunch recovery — the
        // record tables are in-memory only, so every previously stored
        // asset was unreachable after a relaunch (and orphan cleanup would
        // have treated them as garbage). Scan the store directories back
        // into the record tables before anything else touches the store.
        try await assetStore.restoreFromDisk()

        // T284/T285: compose the sync root (vault config store + Keychain +
        // SyncEngine wiring). Loads the persisted configuration/state.
        let syncCoordinator = SyncCoordinator(
            store: store,
            secretStore: KeychainService(),
            deviceId: DeviceIdentity.current.id,
            assetStore: assetStore
        )
        await syncCoordinator.load()

        return AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(directoryURL: assetDirectory, store: assetStore),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(),
            syncCoordinator: syncCoordinator,
            typography: TypographyPreferences.load()
        )
    }
}

// MARK: - Service groupings
//
// Each grouping is a thin Sendable value that carries references to the
// concrete services from the StickyCore modules. Concrete service types
// land per tasks.md Phase 2 (foundational) and per-user-story phases.

public struct DomainServices: Sendable {
    public init() {}
    public static let placeholder = DomainServices()
}

public struct PersistenceServices: Sendable {
    /// The open database store (nil until the app has bootstrapped).
    public let store: DatabaseStore?

    public init(store: DatabaseStore? = nil) {
        self.store = store
    }

    public static let placeholder = PersistenceServices(store: nil)

    // MARK: - Repositories (concrete services composed at startup)

    /// The note + block repository (nil before bootstrap). UI depends on
    /// the `NoteRepository`/`BlockRepository` protocols (plan §Module
    /// boundaries).
    public var noteRepository: (any NoteRepository & BlockRepository)? {
        guard let store else { return nil }
        return SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
    }

    /// The todo repository (nil before bootstrap).
    public var todoRepository: (any TodoRepository)? {
        guard let store else { return nil }
        return SQLiteTodoRepository(store: store)
    }

    /// The tombstone repository (nil before bootstrap).
    public var tombstoneRepository: (any TombstoneRepositoryProtocol)? {
        guard let store else { return nil }
        return SQLiteTombstoneRepository(store: store)
    }

    /// Card projections (lazy card-grid loading, T134/T172).
    public var cardProjection: CardProjection.Type? {
        store != nil ? CardProjection.self : nil
    }

    /// FTS-backed search (T042/T283): matches titles, body, todos, code,
    /// file display names, and screenshot captions. Nil before bootstrap.
    public var searchService: SearchService? {
        guard let store else { return nil }
        return SearchService(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
    }

    /// Device-local window-state repository (T051/T289 — never synced).
    public var windowStateRepository: SQLiteWindowStateRepository? {
        guard let store else { return nil }
        return SQLiteWindowStateRepository(store: store)
    }

    /// Device-local vault configuration + sync-state store (T285).
    public var vaultConfigurationStore: SQLiteVaultConfigurationStore? {
        guard let store else { return nil }
        return SQLiteVaultConfigurationStore(store: store)
    }

    /// Device-local file-locator repository (T291 — bookmark bytes never
    /// sync, FR-105).
    public var fileLocatorRepository: SQLiteFileLocatorRepository? {
        guard let store else { return nil }
        return SQLiteFileLocatorRepository(store: store)
    }

    /// Fetches card projections for the given lifecycle state and sort order
    /// (bounded to 500 rows). When `noteIds` is non-nil (FTS search results),
    /// only those notes are fetched without the row bound (T283).
    public func fetchCards(
        lifecycle: NoteLifecycleState,
        sort: NoteSortKey,
        noteIds: Set<UUID>? = nil
    ) async throws -> [NoteCardProjection] {
        // R1.10 (remediation roadmap 2026-08-14): a missing store is a
        // FAILURE (the database is unavailable), not an empty library —
        // silently returning [] made every pre-bootstrap/placeholder load
        // look like an empty grid and the FR-011a error surface was never
        // exercised.
        guard let store else { throw StickyError.persistence(.databaseOpenFailed) }
        return try await CardProjection.fetchCardProjections(
            store: store,
            lifecycle: lifecycle,
            sort: sort,
            noteIds: noteIds
        )
    }
}

public struct EditorServices: Sendable {
    public init() {}
    public static let placeholder = EditorServices()
}

public struct AssetServices: Sendable {
    /// The asset byte store root (nil until composed with a container URL).
    public let directoryURL: URL?
    /// The composed asset store (T293: T087 AssetStore — originals,
    /// thumbnails, app icons; atomic writes + SHA-256 + dedup). Nil before
    /// bootstrap.
    public let store: AssetStore?

    public init(directoryURL: URL? = nil, store: AssetStore? = nil) {
        self.directoryURL = directoryURL
        self.store = store
    }

    public static let placeholder = AssetServices()
}

public struct SecurityServices: Sendable {
    public init() {}
    public static let placeholder = SecurityServices()
}

public struct SyncServices: Sendable {
    public init() {}
    public static let placeholder = SyncServices()
}

public struct SystemBridgeServices: Sendable {
    public init() {}
    public static let placeholder = SystemBridgeServices()
}

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
/// Until the foundational services (Phase 2) and the user-story UIs (Phase 3+)
/// land, this is a `placeholder` that lets the app compile and run for
/// foundation bring-up. Real composition lands incrementally per tasks.md.
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

    public init(
        domain: DomainServices,
        persistence: PersistenceServices,
        editor: EditorServices,
        assets: AssetServices,
        security: SecurityServices,
        sync: SyncServices,
        systemBridge: SystemBridgeServices,
        localPreferences: LocalPreferences,
        syncCoordinator: SyncCoordinator? = nil
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
    /// 1. `MigrationRecovery.recoverFromInterruptedMigration` — restore the
    ///    pre-migration backup if a previous launch crashed mid-migration.
    /// 2. Open the `DatabasePool` (WAL, foreign keys, bounded busy timeout).
    /// 3. Run pending migrations with pre-migration backup + post-migration
    ///    integrity check (restore-on-failure, never half-migrated).
    ///
    /// The app calls this once at launch; a failure surfaces a
    /// `SchemaCompatibility`-class error and the app refuses to start rather
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
        appGroupContainerURL: URL
    ) async throws -> AppEnvironment {
        let fm = FileManager.default
        let baseURL = appGroupContainerURL.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        try fm.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let databasePath = baseURL
            .appendingPathComponent(DatabaseBootstrap.databaseFileName).path
        let backupPath = DatabaseBootstrap.backupPath(forDatabasePath: databasePath)

        let store = try await DatabaseBootstrap.open(
            databasePath: databasePath,
            backupPath: backupPath
        )

        // T284/T285: compose the sync root (vault config store + Keychain +
        // SyncEngine wiring). Loads the persisted configuration/state.
        let syncCoordinator = SyncCoordinator(
            store: store,
            secretStore: KeychainService(),
            deviceId: DeviceIdentity.current.id
        )
        await syncCoordinator.load()

        return AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(),
            syncCoordinator: syncCoordinator
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

    /// Fetches card projections for the given lifecycle state and sort order
    /// (bounded to 500 rows). When `noteIds` is non-nil (FTS search results),
    /// only those notes are fetched without the row bound (T283).
    public func fetchCards(
        lifecycle: NoteLifecycleState,
        sort: NoteSortKey,
        noteIds: Set<UUID>? = nil
    ) async throws -> [NoteCardProjection] {
        guard let store else { return [] }
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

    public init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL
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

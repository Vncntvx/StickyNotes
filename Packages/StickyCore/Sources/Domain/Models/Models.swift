import Foundation

// MARK: - Domain value types (T011)
//
// Per data-model.md §Entities. All types are Foundation-only, Sendable value
// types (constitution IV — explicit, durable, versioned data). Concrete DB
// rows are NOT exported as contracts (plan §Module boundaries); these Domain
// types are the canonical in-memory representation.
//
// Synchronized vs device-local fields are explicitly separated (constitution
// IV/IX). Synchronized fields appear in canonical JSON; device-local fields
// NEVER appear in canonical JSON or sync.

// MARK: - Note

/// The unit a user creates, edits, and retrieves. Synchronized fields appear
/// in canonical JSON; device-local fields never leave the device.
///
/// Per data-model.md §Note.
public struct Note: Sendable, Identifiable, Equatable, Hashable {
    /// Stable note identity.
    public let id: UUID

    /// Optional manual title; nil means the generated summary is display-only
    /// and never stored (FR-045).
    public var title: String?

    /// Built-in color or custom.
    public var colorKey: NoteColorKey

    /// Hex color (e.g. #RRGGBB) when `colorKey == .custom`; otherwise nil.
    public var customColor: String?

    /// Background transparency (field name retained from v1; semantic is
    /// opacity per FR-041a): 0.40–1.00 inclusive, 0.05 steps, default 1.00.
    public var transparency: Double

    /// Per-note text size in points (FR-043a): 9–24 inclusive, 1-pt steps,
    /// default 13. Text ≥18 pt is large text for the FR-042 thresholds.
    public var textSize: Int

    /// Per-note floating state (FR-036).
    public var alwaysOnTop: Bool

    /// At most one cover screenshot per note; references a screenshot block
    /// id. Enforced transactionally (data-model.md §Constraints).
    public var coverScreenshotBlockId: UUID?

    /// Manual-order sort key (1024-gap convention).
    public var manualSortKey: Int

    /// Lifecycle state (active/trashed/permanentlyDeleted/conflictCopy).
    public var lifecycleState: NoteLifecycleState

    /// Set on trashing; drives 30-day expiry. Local+meta (drives retention
    /// scan; the timestamp itself is not sensitive).
    public var trashedAt: Date?

    /// Set on conflict copies.
    public var conflictOriginNoteId: UUID?
    public var conflictLabel: String?

    /// Version lineage for sync (constitution VIII).
    public var versionId: UUID
    public var parentVersionId: UUID?
    public var lastModifiedDeviceId: UUID
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        colorKey: NoteColorKey = .yellow,
        customColor: String? = nil,
        transparency: Double = 1.0,
        textSize: Int = NoteAppearance.TextSizeBounds.defaultSize,
        alwaysOnTop: Bool = false,
        coverScreenshotBlockId: UUID? = nil,
        manualSortKey: Int = ManualSortKeys.initialSortKey,
        lifecycleState: NoteLifecycleState = .active,
        trashedAt: Date? = nil,
        conflictOriginNoteId: UUID? = nil,
        conflictLabel: String? = nil,
        versionId: UUID = UUID(),
        parentVersionId: UUID? = nil,
        lastModifiedDeviceId: UUID,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.colorKey = colorKey
        self.customColor = customColor
        self.transparency = transparency
        self.textSize = textSize
        self.alwaysOnTop = alwaysOnTop
        self.coverScreenshotBlockId = coverScreenshotBlockId
        self.manualSortKey = manualSortKey
        self.lifecycleState = lifecycleState
        self.trashedAt = trashedAt
        self.conflictOriginNoteId = conflictOriginNoteId
        self.conflictLabel = conflictLabel
        self.versionId = versionId
        self.parentVersionId = parentVersionId
        self.lastModifiedDeviceId = lastModifiedDeviceId
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Convenience: lineage view of this note.
    public var lineage: VersionLineage {
        VersionLineage(
            versionId: versionId,
            parentVersionId: parentVersionId,
            lastModifiedDeviceId: lastModifiedDeviceId,
            modifiedAt: modifiedAt
        )
    }
}

// MARK: - Block

/// Ordered content within a note. Six categories per `BlockKind`. The payload
/// is the canonical block payload (rich-text document, code text, file-ref
/// metadata, image metadata, screenshot association). Device-local locator
/// data lives in a separate table/file (never in payload).
///
/// Per data-model.md §Block and contracts/block-payloads.schema.json.
public struct Block: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let noteId: UUID
    public var kind: BlockKind
    public var sortKey: Int
    /// Kind-specific canonical payload (see CanonicalBlockPayload).
    ///
    /// Stored as an opaque Codable value in the Domain layer; the concrete
    /// `CanonicalBlockPayload` enum lives in CanonicalNote.swift (T015) and
    /// the Persistence layer encodes/decodes it to JSON for SQLite storage.
    public var payload: CanonicalBlockPayload
    public var versionId: UUID
    public var parentVersionId: UUID?
    public var lastModifiedDeviceId: UUID
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        noteId: UUID,
        kind: BlockKind,
        sortKey: Int,
        payload: CanonicalBlockPayload,
        versionId: UUID = UUID(),
        parentVersionId: UUID? = nil,
        lastModifiedDeviceId: UUID,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.noteId = noteId
        self.kind = kind
        self.sortKey = sortKey
        self.payload = payload
        self.versionId = versionId
        self.parentVersionId = parentVersionId
        self.lastModifiedDeviceId = lastModifiedDeviceId
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

// MARK: - TodoItem

/// A todo block's identity/hierarchy. Todo text lives in the block's
/// rich-text payload; identity/hierarchy is separate for stability across
/// reorders/edits (FR-071).
///
/// Per data-model.md §TodoItem.
public struct TodoItem: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let noteId: UUID
    public let blockId: UUID
    public var parentTodoId: UUID?
    public var sortKey: Int
    public var depth: Int
    public var isComplete: Bool
    public var versionId: UUID
    public var parentVersionId: UUID?
    public var lastModifiedDeviceId: UUID
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        noteId: UUID,
        blockId: UUID,
        parentTodoId: UUID? = nil,
        sortKey: Int = ManualSortKeys.initialSortKey,
        depth: Int = 0,
        isComplete: Bool = false,
        versionId: UUID = UUID(),
        parentVersionId: UUID? = nil,
        lastModifiedDeviceId: UUID,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.noteId = noteId
        self.blockId = blockId
        self.parentTodoId = parentTodoId
        self.sortKey = sortKey
        self.depth = depth
        self.isComplete = isComplete
        self.versionId = versionId
        self.parentVersionId = parentVersionId
        self.lastModifiedDeviceId = lastModifiedDeviceId
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

// MARK: - Asset

/// A binary asset stored outside SQLite in the sandbox Application Support
/// directory
/// (originals, thumbnails, app icons). Referenced by blocks.
///
/// Per data-model.md §Asset. Asset bytes are synchronized as independent
/// encrypted objects; `storagePath` is device-local only. `contentHash`
/// enables dedup (two notes pasting the same image share one asset object
/// remotely and can share bytes locally via reference counting).
public struct Asset: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var kind: AssetKind
    public var contentHash: String  // SHA-256 hex
    public var byteSize: Int
    public var contentType: String  // UTType identifier

    // Device-local only — NEVER in canonical JSON.
    public var storagePath: String  // relative path under the sandbox
    public var isSynced: Bool
    public var syncFailureState: AssetSyncFailureState

    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: AssetKind,
        contentHash: String,
        byteSize: Int,
        contentType: String,
        storagePath: String,
        isSynced: Bool = false,
        syncFailureState: AssetSyncFailureState = .none,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.contentType = contentType
        self.storagePath = storagePath
        self.isSynced = isSynced
        self.syncFailureState = syncFailureState
        self.createdAt = createdAt
    }
}

// MARK: - ScreenshotAssociation

/// Metadata linking a screenshot asset to a note block, plus origin context.
/// At most one `isCover = true` per note (enforced in a transaction).
///
/// Per data-model.md §ScreenshotAssociation.
public struct ScreenshotAssociation: Sendable, Equatable, Hashable {
    public let blockId: UUID
    public let noteId: UUID
    public let originalAssetId: UUID
    public let thumbnailAssetId: UUID
    public var appIconAssetId: UUID?
    public var applicationName: String?
    public var windowTitle: String?
    public var caption: String?
    public let capturedAt: Date
    public var isCover: Bool

    public init(
        blockId: UUID,
        noteId: UUID,
        originalAssetId: UUID,
        thumbnailAssetId: UUID,
        appIconAssetId: UUID? = nil,
        applicationName: String? = nil,
        windowTitle: String? = nil,
        caption: String? = nil,
        capturedAt: Date,
        isCover: Bool = false
    ) {
        self.blockId = blockId
        self.noteId = noteId
        self.originalAssetId = originalAssetId
        self.thumbnailAssetId = thumbnailAssetId
        self.appIconAssetId = appIconAssetId
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.caption = caption
        self.capturedAt = capturedAt
        self.isCover = isCover
    }
}

// MARK: - FileReference / FileLocator
//
// These structs now live in their own file per tasks.md T064:
// `Packages/StickyCore/Sources/Domain/Models/FileReference.swift`.

// MARK: - WindowState (device-local)
//
// Per-note window geometry + display preferences. NEVER synchronized. Not
// restored after relaunch is a *behavior* (FR-007); the geometry is still
// stored so a reopened note returns to its frame.

/// Per-note window geometry + display preferences. NEVER synchronized.
/// Per data-model.md §WindowState.
public struct WindowState: Sendable, Equatable {
    public let noteId: UUID
    public var frame: WindowFrame
    public var preferredDisplayUUID: String?
    public var fallbackFrame: WindowFrame?
    public var isOpen: Bool
    public var lastOpenedAt: Date?

    public init(
        noteId: UUID,
        frame: WindowFrame,
        preferredDisplayUUID: String? = nil,
        fallbackFrame: WindowFrame? = nil,
        isOpen: Bool = false,
        lastOpenedAt: Date? = nil
    ) {
        self.noteId = noteId
        self.frame = frame
        self.preferredDisplayUUID = preferredDisplayUUID
        self.fallbackFrame = fallbackFrame
        self.isOpen = isOpen
        self.lastOpenedAt = lastOpenedAt
    }
}

/// {x, y, w, h} preferred window frame. Stored as JSON in WindowState.
public struct WindowFrame: Sendable, Codable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - Tombstone

/// Deletion record for synchronization. Retained 30 days (sync-safety-gated)
/// so a returning offline device doesn't resurrect a deleted note (constitution
/// VIII; data-model.md §Tombstone lifecycle).
public struct Tombstone: Sendable, Equatable, Hashable {
    public let noteId: UUID
    public let deletedVersionId: UUID
    public let parentVersionId: UUID?
    public let deletingDeviceId: UUID
    public let deletedAt: Date

    // Device-local only — NEVER in canonical JSON.
    public var purgedAt: Date?
    public var canPurgeRemote: Bool

    public init(
        noteId: UUID,
        deletedVersionId: UUID,
        parentVersionId: UUID? = nil,
        deletingDeviceId: UUID,
        deletedAt: Date = Date(),
        purgedAt: Date? = nil,
        canPurgeRemote: Bool = false
    ) {
        self.noteId = noteId
        self.deletedVersionId = deletedVersionId
        self.parentVersionId = parentVersionId
        self.deletingDeviceId = deletingDeviceId
        self.deletedAt = deletedAt
        self.purgedAt = purgedAt
        self.canPurgeRemote = canPurgeRemote
    }
}

// MARK: - SyncState (device-local)
//
// Per-vault synchronization scheduling/progress. NEVER synchronized.

/// Per-vault sync run state. NEVER synchronized. Distinct from the
/// per-entity `SyncVersionState` enum. Codable for device-local persistence
/// (the App's sync-state store; never syncs).
public struct SyncState: Sendable, Equatable, Codable {
    public let vaultId: UUID
    public var providerType: ProviderType
    public var lastSuccessfulSyncAt: Date?
    public var lastError: String?  // sanitized error code
    public var inProgress: Bool
    public var pendingSince: Date?
    /// Endpoint/region/bucket/prefix; NO secrets. Secrets live in Keychain.
    public var config: RedactedSyncConfig

    public init(
        vaultId: UUID,
        providerType: ProviderType,
        lastSuccessfulSyncAt: Date? = nil,
        lastError: String? = nil,
        inProgress: Bool = false,
        pendingSince: Date? = nil,
        config: RedactedSyncConfig
    ) {
        self.vaultId = vaultId
        self.providerType = providerType
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastError = lastError
        self.inProgress = inProgress
        self.pendingSince = pendingSince
        self.config = config
    }
}

/// Redacted provider config — endpoint/region/bucket/prefix only. NO secrets
/// (constitution VI/VIII; secrets live in Keychain).
public struct RedactedSyncConfig: Sendable, Codable, Equatable {
    public var endpoint: String
    public var region: String?
    public var bucket: String?
    public var prefix: String?

    public init(endpoint: String, region: String? = nil, bucket: String? = nil, prefix: String? = nil) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.prefix = prefix
    }
}

// MARK: - DeviceIdentity

/// Stable identity for the local device. `displayName` is local-only (NOT
/// synced as meaningful metadata — constitution VI; data-model.md
/// §DeviceIdentity).
public struct DeviceIdentity: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var displayName: String  // local-only
    public let createdAt: Date

    public init(id: UUID = UUID(), displayName: String, createdAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

// MARK: - VaultConfiguration (device-local reference)
//
// Points at a configured vault + provider. Secrets live in Keychain, NOT
// here (constitution VII/VIII; data-model.md §VaultConfiguration).
//
// Per FR-162a (clarified 2026-08-07): `rememberedUnlock` is an enum
// (disabled / enabledUntilLockOrRestart) — NOT a bare Bool. The boot
// timestamp + Keychain ref support the launch-unlock + toggle-off behavior.
// Per FR-154 (clarified 2026-08-07): `replacedFromVaultLocator` records a
// prior vault locator when the user replaced the repository.

/// The remember-unlock lifetime (FR-162a, clarified 2026-08-07).
public enum RememberedUnlock: String, Sendable, Codable, Equatable {
    /// Password required on every sync-triggering app launch (default).
    case disabled
    /// The unwrapped vault key may be stored in a Keychain item so ordinary
    /// app relaunches do not re-prompt. MUST NOT survive logout/restart
    /// (not a login-item daemon). Cleared on explicit lock.
    case enabledUntilLockOrRestart
}

/// Device-local reference to a configured vault + provider. Secrets live in
/// Keychain (referenced by `keychainCredentialRef`), NEVER here.
/// Codable for device-local persistence (the App's vault-configuration
/// store; the row never participates in sync).
public struct VaultConfiguration: Sendable, Equatable, Codable {
    public let vaultId: UUID
    public var vaultLocator: String  // opaque random remote locator
    public var providerType: ProviderType
    public var providerConfig: RedactedSyncConfig
    public var keychainCredentialRef: String  // account label, no secret value
    /// Remember-unlock lifetime (FR-162a). Replaces the legacy `rememberedUnlock: Bool`.
    public var rememberedUnlock: RememberedUnlock
    /// Keychain account label for the remembered unwrapped key, only when
    /// `rememberedUnlock != .disabled`. Cleared on explicit lock.
    public var rememberedUnlockKeychainRef: String?
    /// System boot timestamp captured at remember-time, used to detect Mac
    /// restart (FR-162a). On app launch, if the current boot timestamp
    /// differs, the remembered key is treated as stale and the password is
    /// required.
    public var rememberedUnlockBootTimestamp: Int?
    /// When this vault replaced a prior one (FR-154), the prior locator is
    /// recorded here for user reference; the prior remote data is NOT
    /// auto-deleted.
    public var replacedFromVaultLocator: String?
    public let createdAt: Date

    public init(
        vaultId: UUID,
        vaultLocator: String,
        providerType: ProviderType,
        providerConfig: RedactedSyncConfig,
        keychainCredentialRef: String,
        rememberedUnlock: RememberedUnlock = .disabled,
        rememberedUnlockKeychainRef: String? = nil,
        rememberedUnlockBootTimestamp: Int? = nil,
        replacedFromVaultLocator: String? = nil,
        createdAt: Date = Date()
    ) {
        self.vaultId = vaultId
        self.vaultLocator = vaultLocator
        self.providerType = providerType
        self.providerConfig = providerConfig
        self.keychainCredentialRef = keychainCredentialRef
        self.rememberedUnlock = rememberedUnlock
        self.rememberedUnlockKeychainRef = rememberedUnlockKeychainRef
        self.rememberedUnlockBootTimestamp = rememberedUnlockBootTimestamp
        self.replacedFromVaultLocator = replacedFromVaultLocator
        self.createdAt = createdAt
    }
}

// MARK: - SearchDocument (FTS5 projection)
//
// One searchable row per note. Rebuilt transactionally on note change. The
/// FTS5 table `notes_fts` lives in Persistence; this Domain type is the
/// projection used to build/maintain it.
public struct SearchDocument: Sendable, Equatable {
    public let noteId: UUID
    public var title: String         // Note.title (manual)
    public var summary: String       // generated summary source text
    public var body: String          // concatenated rich-text plain text
    public var todos: String         // todo plain text
    public var code: String          // code-block text
    public var fileNames: String     // file-reference display names
    public var captions: String      // screenshot captions
    public var ocr: String           // future OCR text; empty in v1

    public init(
        noteId: UUID,
        title: String,
        summary: String,
        body: String,
        todos: String,
        code: String,
        fileNames: String,
        captions: String,
        ocr: String = ""
    ) {
        self.noteId = noteId
        self.title = title
        self.summary = summary
        self.body = body
        self.todos = todos
        self.code = code
        self.fileNames = fileNames
        self.captions = captions
        self.ocr = ocr
    }

    /// Empty document for a fresh note.
    public static func empty(for noteId: UUID) -> SearchDocument {
        SearchDocument(
            noteId: noteId,
            title: "",
            summary: "",
            body: "",
            todos: "",
            code: "",
            fileNames: "",
            captions: "",
            ocr: ""
        )
    }
}

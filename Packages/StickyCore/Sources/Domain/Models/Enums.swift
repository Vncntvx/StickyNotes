import Foundation

// MARK: - Domain enums (T012)
//
// Per data-model.md §Entities and contracts/*.schema.json. All enums are
// Foundation-only, Sendable, and persist as language-neutral strings in
// canonical JSON (constitution XIV — no localized strings as protocol
// identifiers).

/// The six block categories per spec FR-064 / data-model.md §Block.
public enum BlockKind: String, Sendable, Codable, CaseIterable {
    case richText
    case todo
    case code
    case fileRef
    case image
    case screenshot
}

/// Built-in note colors per spec FR-031. `custom` defers to `customColor`.
public enum NoteColorKey: String, Sendable, Codable, CaseIterable {
    case yellow
    case pink
    case purple
    case blue
    case green
    case gray
    case custom
}

// FR-043a (clarified 2026-08-07): per-note text size is the integer point
// size (9–24 inclusive, 1-pt steps, default 13). The legacy
// small/regular/large/extraLarge enum was superseded; see NoteAppearance.swift
// (`NoteAppearance.TextSizeBounds`) and Note.textSize: Int.

/// Note lifecycle state per data-model.md §Note lifecycle. Distinguishes
/// active, trashed (30-day recovery), permanentlyDeleted (tombstone only),
/// and conflictCopy (recovered from sync divergence).
public enum NoteLifecycleState: String, Sendable, Codable, CaseIterable {
    case active
    case trashed
    case permanentlyDeleted
    case conflictCopy
}

/// File-reference availability per data-model.md §File reference availability.
/// Drives the relink UX (FR-103) and the card indicator (FR-100). Device-local
/// only; never synced.
///
/// FR-100 (clarified 2026-08-07) — the indicator MUST distinguish four
/// states by more than color alone (FR-044):
/// - `available`: bookmark resolves to an existing file.
/// - `missing`: file unavailable; relink offered (FR-103).
/// - `stale`: bookmark unresolved but the file may still exist (e.g. the
///   last resolved path no longer matches).
/// - `onAnotherDevice`: synchronized generic metadata with no local file
///   (FR-104) — never implies the file is missing.
/// `relinked` is a transient post-relink state before the next verification.
public enum FileAvailability: String, Sendable, Codable, CaseIterable {
    case available
    case stale
    case missing
    case relinked
    case onAnotherDevice
}

/// Per-entity sync lineage state per data-model.md §SyncVersionState.
/// Drives the sync engine's divergence detection and conflict-copy logic
/// (constitution VIII; plan §Conflict model).
public enum SyncVersionState: String, Sendable, Codable, CaseIterable {
    /// Local change not yet pushed (`isDirty = true`, new `versionId`).
    case unsynchronizedLocalModification

    /// Confirmed remote (`isDirty = false`,
    /// `lastSyncedVersionId = versionId`).
    case synchronizedVersion

    /// Local and remote `versionId` differ but share a common ancestor in
    /// `parentVersionId` lineage → conflict copy will be created.
    case divergentVersion

    /// Asset metadata synced but bytes failed; marked in
    /// `Asset.syncFailureState`; retried without re-encrypting metadata.
    case partialAssetSyncFailure
}

/// Asset kind per data-model.md §Asset. Originals, thumbnails, and app-icon
/// snapshots are stored as separate Asset rows with the same `contentHash`
/// enabling dedup.
public enum AssetKind: String, Sendable, Codable, CaseIterable {
    case original
    case thumbnail
    case appIcon
}

/// Asset partial-sync-failure marker per data-model.md §Asset. Device-local
/// only; never synced.
public enum AssetSyncFailureState: String, Sendable, Codable, CaseIterable {
    case none
    case uploadFailed
    case downloadFailed
    case integrityMismatch
}

/// Provider type per data-model.md §SyncState / §VaultConfiguration. One
/// repository at a time (FR-154).
public enum ProviderType: String, Sendable, Codable, CaseIterable {
    case webdav
    case s3
}

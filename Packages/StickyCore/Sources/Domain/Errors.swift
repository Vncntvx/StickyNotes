import Foundation

// MARK: - Typed error categories (T023)
//
// Per plan §Error model. Typed categories: Persistence, EditorConversion,
// AssetStorage, FileRefAccess, Capture, Permission, Encryption, Credentials,
// WebDAV, S3, SyncConflict, RemoteCorruption, SchemaCompatibility. Mapped
// to: silent retry / non-blocking status / inline recovery / blocking
// confirmation (destructive only). User-facing messages localized, no
// sensitive technical detail; diagnostics sanitized (constitution VI).

/// The top-level sticky-core error. Each case carries a sanitized,
/// non-sensitive code suitable for logging and diagnostics export.
///
/// Per plan §Diagnostics: logs/diagnostics NEVER include content/titles/
/// todo/code/file names/paths/window titles/captions/credentials/passwords/
/// key material/complete responses/full object names where avoidable. Stable
/// error domains + sanitized codes only.
public enum StickyError: Error, Sendable {
    case persistence(PersistenceError)
    case editorConversion(EditorConversionError)
    case assetStorage(AssetStorageError)
    case fileRefAccess(FileRefAccessError)
    case capture(CaptureError)
    case permission(PermissionError)
    case encryption(EncryptionError)
    case credentials(CredentialsError)
    case webdav(WebDAVError)
    case s3(S3Error)
    case syncConflict(SyncConflictError)
    case remoteCorruption(RemoteCorruptionError)
    case schemaCompatibility(SchemaCompatibilityError)

    /// A stable, sanitized error code suitable for logs and exported
    /// diagnostics. Contains NO note content, paths, or secrets.
    public var sanitizedCode: String {
        switch self {
        case .persistence(let e): return "persistence.\(e.sanitizedCode)"
        case .editorConversion(let e): return "editorConversion.\(e.sanitizedCode)"
        case .assetStorage(let e): return "assetStorage.\(e.sanitizedCode)"
        case .fileRefAccess(let e): return "fileRefAccess.\(e.sanitizedCode)"
        case .capture(let e): return "capture.\(e.sanitizedCode)"
        case .permission(let e): return "permission.\(e.sanitizedCode)"
        case .encryption(let e): return "encryption.\(e.sanitizedCode)"
        case .credentials(let e): return "credentials.\(e.sanitizedCode)"
        case .webdav(let e): return "webdav.\(e.sanitizedCode)"
        case .s3(let e): return "s3.\(e.sanitizedCode)"
        case .syncConflict(let e): return "syncConflict.\(e.sanitizedCode)"
        case .remoteCorruption(let e): return "remoteCorruption.\(e.sanitizedCode)"
        case .schemaCompatibility(let e): return "schemaCompatibility.\(e.sanitizedCode)"
        }
    }
}

// MARK: - Persistence

public enum PersistenceError: Error, Sendable {
    case databaseOpenFailed
    case migrationFailed
    case writeConflict            // SQLITE_BUSY
    case integrityCheckFailed
    case recoveryFailed
    case recordNotFound
    case invalidPayload
    /// The App Group container could not be resolved at launch (sandbox/
    /// entitlement mismatch). Surfaced non-blockingly (FR-011a).
    case containerUnavailable
    /// FR-090b: note structured content exceeds `ScaleLimits.maxNoteContentBytes`
    /// (5 MB). The write was refused; the last valid saved state is preserved.
    case contentTooLarge

    public var sanitizedCode: String {
        switch self {
        case .databaseOpenFailed: return "databaseOpenFailed"
        case .migrationFailed: return "migrationFailed"
        case .writeConflict: return "writeConflict"
        case .integrityCheckFailed: return "integrityCheckFailed"
        case .recoveryFailed: return "recoveryFailed"
        case .recordNotFound: return "recordNotFound"
        case .invalidPayload: return "invalidPayload"
        case .contentTooLarge: return "contentTooLarge"
        case .containerUnavailable: return "containerUnavailable"
        }
    }
}

// MARK: - Editor conversion

public enum EditorConversionError: Error, Sendable {
    case unsupportedMarkStripped
    case offsetOutOfRange
    case normalizationFailed
    case invalidRichTextDocument

    public var sanitizedCode: String {
        switch self {
        case .unsupportedMarkStripped: return "unsupportedMarkStripped"
        case .offsetOutOfRange: return "offsetOutOfRange"
        case .normalizationFailed: return "normalizationFailed"
        case .invalidRichTextDocument: return "invalidRichTextDocument"
        }
    }
}

// MARK: - Asset storage

public enum AssetStorageError: Error, Sendable {
    case writeFailed
    case renameFailed
    case hashMismatch
    case orphanCleanupFailed
    case thumbnailGenerationFailed
    case exportFailed

    public var sanitizedCode: String {
        switch self {
        case .writeFailed: return "writeFailed"
        case .renameFailed: return "renameFailed"
        case .hashMismatch: return "hashMismatch"
        case .orphanCleanupFailed: return "orphanCleanupFailed"
        case .thumbnailGenerationFailed: return "thumbnailGenerationFailed"
        case .exportFailed: return "exportFailed"
        }
    }
}

// MARK: - File reference access

public enum FileRefAccessError: Error, Sendable {
    case bookmarkStale
    case bookmarkMissing
    case fileMissing
    case startAccessFailed
    case moveFailed
    case moveVerifyFailed

    public var sanitizedCode: String {
        switch self {
        case .bookmarkStale: return "bookmarkStale"
        case .bookmarkMissing: return "bookmarkMissing"
        case .fileMissing: return "fileMissing"
        case .startAccessFailed: return "startAccessFailed"
        case .moveFailed: return "moveFailed"
        case .moveVerifyFailed: return "moveVerifyFailed"
        }
    }
}

// MARK: - Capture

public enum CaptureError: Error, Sendable {
    case permissionDenied
    case noDisplayAvailable
    case captureStreamFailed
    case regionSelectionCanceled
    case coordinateConversionFailed

    public var sanitizedCode: String {
        switch self {
        case .permissionDenied: return "permissionDenied"
        case .noDisplayAvailable: return "noDisplayAvailable"
        case .captureStreamFailed: return "captureStreamFailed"
        case .regionSelectionCanceled: return "regionSelectionCanceled"
        case .coordinateConversionFailed: return "coordinateConversionFailed"
        }
    }
}

// MARK: - Permissions

public enum PermissionError: Error, Sendable {
    case screenRecordingDenied
    case screenRecordingNotDetermined
    case accessibilityDenied
    case accessibilityNotDetermined

    public var sanitizedCode: String {
        switch self {
        case .screenRecordingDenied: return "screenRecordingDenied"
        case .screenRecordingNotDetermined: return "screenRecordingNotDetermined"
        case .accessibilityDenied: return "accessibilityDenied"
        case .accessibilityNotDetermined: return "accessibilityNotDetermined"
        }
    }
}

// MARK: - Encryption

/// Fail-closed encryption errors (constitution VII). None of these expose
/// keys, nonces-as-identifiers, or ciphertext details in their codes.
///
/// Per FR-160d (clarified 2026-08-07) the eight enumerated fail-closed
/// inputs each map to a distinct case: (a) wrongPassword, (b)
/// modifiedCiphertext, (c) invalidTag, (d) wrongObjectId, (e)
/// wrongObjectType, (f) wrongVaultContext, (g) unsupportedEnvelopeVersion,
/// (h) corruptEnvelopeStructure. The legacy `wrongObjectContext` is
/// retained as a convenience umbrella for code paths that have not yet
/// been updated to distinguish the specific mismatch; new code SHOULD use
/// the specific case (Constitution VII).
public enum EncryptionError: Error, Sendable {
    case wrongPassword              // (a) fail-closed
    case modifiedCiphertext         // (b) fail-closed (bit-flip/truncation/extension)
    case invalidTag                 // (c) fail-closed (AES-GCM auth tag mismatch)
    case wrongObjectContext         // legacy umbrella — prefer the specific case below
    case wrongObjectId              // (d) fail-closed (object ID mismatch in AAD)
    case wrongObjectType            // (e) fail-closed (object type mismatch in AAD)
    case wrongVaultContext          // (f) fail-closed (vault ID mismatch in AAD)
    case unsupportedEnvelopeVersion // (g) fail-closed
    case corruptEnvelopeStructure   // (h) fail-closed (truncated/malformed envelope)
    case keychainUnavailable
    case corruptBootstrap           // fail-closed
    case kdfFailed

    public var sanitizedCode: String {
        switch self {
        case .wrongPassword: return "wrongPassword"
        case .modifiedCiphertext: return "modifiedCiphertext"
        case .invalidTag: return "invalidTag"
        case .wrongObjectContext: return "wrongObjectContext"
        case .wrongObjectId: return "wrongObjectId"
        case .wrongObjectType: return "wrongObjectType"
        case .wrongVaultContext: return "wrongVaultContext"
        case .unsupportedEnvelopeVersion: return "unsupportedEnvelopeVersion"
        case .corruptEnvelopeStructure: return "corruptEnvelopeStructure"
        case .keychainUnavailable: return "keychainUnavailable"
        case .corruptBootstrap: return "corruptBootstrap"
        case .kdfFailed: return "kdfFailed"
        }
    }
}

// MARK: - Credentials

public enum CredentialsError: Error, Sendable {
    case notFound
    case accessDenied
    case saveFailed
    case deleteFailed
    /// Wrong vault detected (FR edge case, clarified 2026-08-07): the
    /// bootstrap object's `vaultId` does not match the locally-configured
    /// `vaultId`, or a bootstrap already exists under the chosen locator
    /// for a new vault. Fail-closed; no local/remote mutation.
    case wrongVault
    /// The configured provider endpoint is malformed (app composition, T285).
    case invalidEndpoint
    /// No vault is currently configured (app composition, T285).
    case notConfigured

    public var sanitizedCode: String {
        switch self {
        case .notFound: return "notFound"
        case .accessDenied: return "accessDenied"
        case .saveFailed: return "saveFailed"
        case .deleteFailed: return "deleteFailed"
        case .wrongVault: return "wrongVault"
        case .invalidEndpoint: return "invalidEndpoint"
        case .notConfigured: return "notConfigured"
        }
    }
}

// MARK: - Provider errors (WebDAV, S3)

/// WebDAV adapter errors. Per research.md R10: subset of PROPFIND/MKCOL/GET/
/// PUT/HEAD/DELETE + ETag/If-Match/If-None-Match.
public enum WebDAVError: Error, Sendable {
    case authFailed
    case conditionalCreateFailed     // If-None-Match: * conflict
    case conditionalReplaceFailed    // If-Match mismatch
    case missing
    case serverError
    case timeout
    case canceled
    case tlsFailed
    case redirectLoop
    case capabilityUnsupported       // server lacks conditional writes

    public var sanitizedCode: String {
        switch self {
        case .authFailed: return "authFailed"
        case .conditionalCreateFailed: return "conditionalCreateFailed"
        case .conditionalReplaceFailed: return "conditionalReplaceFailed"
        case .missing: return "missing"
        case .serverError: return "serverError"
        case .timeout: return "timeout"
        case .canceled: return "canceled"
        case .tlsFailed: return "tlsFailed"
        case .redirectLoop: return "redirectLoop"
        case .capabilityUnsupported: return "capabilityUnsupported"
        }
    }
}

/// S3-compatible adapter errors. Per research.md R11: SigV4, conditional
/// writes, ETag variance across AWS/R2/MinIO/B2.
public enum S3Error: Error, Sendable {
    case authFailed
    case sigV4Failed
    case conditionalCreateFailed
    case conditionalReplaceFailed
    case missing
    case serverError
    case timeout
    case canceled
    case tlsFailed
    case clockSkew
    case etagMismatch

    public var sanitizedCode: String {
        switch self {
        case .authFailed: return "authFailed"
        case .sigV4Failed: return "sigV4Failed"
        case .conditionalCreateFailed: return "conditionalCreateFailed"
        case .conditionalReplaceFailed: return "conditionalReplaceFailed"
        case .missing: return "missing"
        case .serverError: return "serverError"
        case .timeout: return "timeout"
        case .canceled: return "canceled"
        case .tlsFailed: return "tlsFailed"
        case .clockSkew: return "clockSkew"
        case .etagMismatch: return "etagMismatch"
        }
    }
}

// MARK: - Sync conflict / remote corruption / schema compatibility

/// Non-destructive sync conflict errors (constitution VIII).
public enum SyncConflictError: Error, Sendable {
    case divergenceDetected
    case conflictCopyCreated
    case deleteEditConflict
    case manifestPreconditionFailed
    case longOfflineReconciliationRequired

    public var sanitizedCode: String {
        switch self {
        case .divergenceDetected: return "divergenceDetected"
        case .conflictCopyCreated: return "conflictCopyCreated"
        case .deleteEditConflict: return "deleteEditConflict"
        case .manifestPreconditionFailed: return "manifestPreconditionFailed"
        case .longOfflineReconciliationRequired: return "longOfflineReconciliationRequired"
        }
    }
}

/// Remote corruption errors. Fail-closed (constitution VII/VIII): the engine
/// does NOT silently accept corrupt remote objects.
public enum RemoteCorruptionError: Error, Sendable {
    case invalidEnvelope
    case manifestInvalid
    case objectHashMismatch
    case unexpectedObjectLayout

    public var sanitizedCode: String {
        switch self {
        case .invalidEnvelope: return "invalidEnvelope"
        case .manifestInvalid: return "manifestInvalid"
        case .objectHashMismatch: return "objectHashMismatch"
        case .unexpectedObjectLayout: return "unexpectedObjectLayout"
        }
    }
}

/// Schema compatibility errors. The widget falls back to privacy-safe
/// placeholders on schema mismatch (research.md R6).
public enum SchemaCompatibilityError: Error, Sendable {
    case unsupportedSchemaVersion
    case widgetSchemaMismatch

    public var sanitizedCode: String {
        switch self {
        case .unsupportedSchemaVersion: return "unsupportedSchemaVersion"
        case .widgetSchemaMismatch: return "widgetSchemaMismatch"
        }
    }
}

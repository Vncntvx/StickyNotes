import Foundation
import Domain

// MARK: - DiagnosticBundle (T185, FR-191 clarified 2026-08-07)
//
// Per contracts/diagnostic-bundle.schema.json and data-model.md
// §DiagnosticSnapshot: the user-exportable diagnostic bundle. This is a
// POSITIVE content boundary — only the fields enumerated in the schema are
// permitted. Any field not listed is excluded by default. No note content,
// titles, summaries, captions, file names/paths, window titles, credentials,
// passwords, key material, raw server responses, or remote object names
// appear in this bundle.
//
// The bundle is generated from a `DiagnosticSnapshot` (the collected,
// sanitized inputs) and validated against the JSON Schema before export.

/// The user-exportable diagnostic bundle (schema version 1). Per FR-191
/// (clarified 2026-08-07), this is a POSITIVE content boundary: only the
/// fields enumerated in `contracts/diagnostic-bundle.schema.json` are
/// permitted. Any field not listed is excluded by default.
public struct DiagnosticBundle: Sendable, Equatable, Codable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var appVersion: String
    public var osVersion: String
    public var schemaVersionLocal: Int
    /// Sync provider type, or nil if sync is unconfigured. NEVER the
    /// endpoint URL, hostname, or credentials.
    public var providerType: String?
    /// Normalized provider error events from the last 30 days. NEVER raw
    /// server responses or bodies.
    public var recentErrorEvents: [DiagnosticErrorEvent]
    /// Synchronization run counts + durations. NEVER payloads or object names.
    public var syncRunCounts: DiagnosticSyncRunCounts?
    /// Aggregate counts of notes / blocks / assets. NEVER titles, summaries,
    /// captions, or content.
    public var objectCounts: DiagnosticObjectCounts
    /// Vault state at generation time. NEVER the password or derived key.
    public var vaultState: DiagnosticVaultState
    /// Boolean granted-or-denied statuses for relevant system permissions.
    public var permissionStatuses: DiagnosticPermissionStatuses
    public var generatedAt: Date?

    public init(
        schemaVersion: Int = DiagnosticBundle.schemaVersion,
        appVersion: String,
        osVersion: String,
        schemaVersionLocal: Int,
        providerType: String? = nil,
        recentErrorEvents: [DiagnosticErrorEvent] = [],
        syncRunCounts: DiagnosticSyncRunCounts? = nil,
        objectCounts: DiagnosticObjectCounts,
        vaultState: DiagnosticVaultState,
        permissionStatuses: DiagnosticPermissionStatuses,
        generatedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.schemaVersionLocal = schemaVersionLocal
        self.providerType = providerType
        self.recentErrorEvents = recentErrorEvents
        self.syncRunCounts = syncRunCounts
        self.objectCounts = objectCounts
        self.vaultState = vaultState
        self.permissionStatuses = permissionStatuses
        self.generatedAt = generatedAt
    }
}

/// A normalized provider error event (timestamp + category). NEVER raw
/// server responses or bodies. The category enum matches
/// `contracts/diagnostic-bundle.schema.json` +
/// `contracts/provider-errors.md`.
public struct DiagnosticErrorEvent: Sendable, Equatable, Codable {
    public var timestamp: Date
    public var normalizedErrorCategory: String

    public init(timestamp: Date, normalizedErrorCategory: String) {
        self.timestamp = timestamp
        self.normalizedErrorCategory = normalizedErrorCategory
    }

    /// The allowed error categories per the schema.
    public static let allowedCategories: Set<String> = [
        "auth", "forbidden", "conditionalFailed", "notFound", "conflict",
        "network", "server", "clockSkew", "corrupt", "schemaUnsupported",
        "canceled", "tls", "wrongVault", "unknown"
    ]
}

/// Sync run counts + durations. NEVER payloads or object names.
public struct DiagnosticSyncRunCounts: Sendable, Equatable, Codable {
    public var last24h: Int
    public var last7d: Int
    public var last30d: Int
    public var averageDurationMs: Double?

    public init(last24h: Int = 0, last7d: Int = 0, last30d: Int = 0, averageDurationMs: Double? = nil) {
        self.last24h = last24h
        self.last7d = last7d
        self.last30d = last30d
        self.averageDurationMs = averageDurationMs
    }
}

/// Aggregate counts of notes / blocks / assets. NEVER titles, summaries,
/// captions, or content.
public struct DiagnosticObjectCounts: Sendable, Equatable, Codable {
    public var notes: Int
    public var blocks: Int
    public var assets: Int

    public init(notes: Int = 0, blocks: Int = 0, assets: Int = 0) {
        self.notes = notes
        self.blocks = blocks
        self.assets = assets
    }
}

/// Vault state at generation time. NEVER the password or derived key.
public enum DiagnosticVaultState: String, Sendable, Codable, Equatable {
    case locked
    case unlocked
    case unconfigured
}

/// Boolean granted-or-denied statuses for system permissions.
public struct DiagnosticPermissionStatuses: Sendable, Equatable, Codable {
    public var screenRecording: Bool
    public var accessibility: Bool

    public init(screenRecording: Bool, accessibility: Bool) {
        self.screenRecording = screenRecording
        self.accessibility = accessibility
    }
}

// MARK: - DiagnosticBundleGenerator
//
// Generates a `DiagnosticBundle` from the sanitized inputs. The generator
// enforces the positive content boundary: only the enumerated fields are
// included; any caller-supplied field not in the schema is dropped. The
// generator also validates that error-event categories are within the
// allowed set (unknown categories are mapped to "unknown").

public enum DiagnosticBundleGenerator {

    /// Generates a diagnostic bundle from the sanitized snapshot inputs.
    /// The `providerType` is derived from the `VaultConfiguration`'s
    /// `providerType` (or nil when sync is unconfigured). The generator
    /// NEVER touches note content, titles, paths, credentials, or raw
    /// server responses.
    public static func generate(
        appVersion: String,
        osVersion: String,
        schemaVersionLocal: Int,
        providerType: ProviderType?,
        recentErrorEvents: [DiagnosticErrorEvent],
        syncRunCounts: DiagnosticSyncRunCounts?,
        objectCounts: DiagnosticObjectCounts,
        vaultState: DiagnosticVaultState,
        permissionStatuses: DiagnosticPermissionStatuses,
        generatedAt: Date = Date()
    ) -> DiagnosticBundle {
        // Sanitize error-event categories: map any out-of-set category to
        // "unknown" so the bundle always validates against the schema.
        let sanitizedEvents = recentErrorEvents.map { event in
            DiagnosticErrorEvent(
                timestamp: event.timestamp,
                normalizedErrorCategory: DiagnosticErrorEvent.allowedCategories.contains(event.normalizedErrorCategory)
                    ? event.normalizedErrorCategory
                    : "unknown"
            )
        }
        return DiagnosticBundle(
            appVersion: appVersion,
            osVersion: osVersion,
            schemaVersionLocal: schemaVersionLocal,
            providerType: providerType?.rawValue,
            recentErrorEvents: sanitizedEvents,
            syncRunCounts: syncRunCounts,
            objectCounts: objectCounts,
            vaultState: vaultState,
            permissionStatuses: permissionStatuses,
            generatedAt: generatedAt
        )
    }

    /// Encodes the bundle to canonical JSON (stable keys, ISO 8601 UTC).
    public static func encode(_ bundle: DiagnosticBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }
}

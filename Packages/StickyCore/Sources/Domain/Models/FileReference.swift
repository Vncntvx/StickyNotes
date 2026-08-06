import Foundation

// MARK: - FileReference + FileLocator models (T064)
//
// Per data-model.md §FileReference (synchronized metadata) and §FileLocator
// (device-local). Constitution IX: file references are references (not
// cloud attachments). Only generic metadata syncs; bookmark bytes + absolute
// paths NEVER appear in canonical JSON.
//
// These structs were originally defined in Models.swift; they live here per
// tasks.md T064's explicit path contract.

// MARK: - FileReference (synchronized metadata)
//
// Generic, safe metadata for a file-reference block. NO bookmark bytes, NO
// absolute paths (constitution IX; data-model.md §FileReference).

/// Synchronized metadata for a file-reference block. Bookmark bytes and
/// absolute paths MUST NEVER appear here (constitution IX; contracts/
/// block-payloads.schema.json).
public struct FileReference: Sendable, Equatable, Hashable {
    public let blockId: UUID
    public var displayName: String
    public var contentType: String  // UTType identifier
    public var approximateSize: Int?
    public let originDeviceId: UUID
    public let addedAt: Date
    public var caption: String?

    public init(
        blockId: UUID,
        displayName: String,
        contentType: String,
        approximateSize: Int? = nil,
        originDeviceId: UUID,
        addedAt: Date = Date(),
        caption: String? = nil
    ) {
        self.blockId = blockId
        self.displayName = displayName
        self.contentType = contentType
        self.approximateSize = approximateSize
        self.originDeviceId = originDeviceId
        self.addedAt = addedAt
        self.caption = caption
    }
}

// MARK: - FileLocator (device-local)
//
// Durable local access to a referenced file. NEVER synchronized. Bookmark
// bytes + absolute paths live here only.

/// Device-local locator for durable access to a referenced file. NEVER
/// synchronized (constitution IX; data-model.md §FileLocator).
public struct FileLocator: Sendable, Equatable {
    public let blockId: UUID
    public var bookmarkData: Data  // security-scoped bookmark bytes
    public var lastResolvedPath: String  // for display / stale check only
    public var availabilityStatus: FileAvailability
    public var stale: Bool
    public var verifiedAt: Date?

    public init(
        blockId: UUID,
        bookmarkData: Data,
        lastResolvedPath: String,
        availabilityStatus: FileAvailability,
        stale: Bool,
        verifiedAt: Date? = nil
    ) {
        self.blockId = blockId
        self.bookmarkData = bookmarkData
        self.lastResolvedPath = lastResolvedPath
        self.availabilityStatus = availabilityStatus
        self.stale = stale
        self.verifiedAt = verifiedAt
    }
}

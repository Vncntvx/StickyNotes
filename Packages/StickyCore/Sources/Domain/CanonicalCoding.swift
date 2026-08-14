import Foundation

// MARK: - Deterministic canonical JSON coding (T016)
//
// Per plan §Canonical note representation and contracts/*.schema.json:
//
// - Stable keys (alphabetical ordering is NOT required by JSON, but the
//   encoded output is deterministic for a given input — same input → same
//   bytes — which matters for SHA-256 content hashing and for stable diffs).
// - ISO 8601 UTC timestamps with a fixed format and `Z` suffix.
// - UUID strings (lowercase, canonical 8-4-4-4-12 form).
// - Explicit `schemaVersion` on every canonical type.
// - No Swift type names, no platform archives, no local paths, no bookmark
//   bytes (constitution IV/IX).
//
// The encoder/decoder below are the canonical boundaries. Domain types use
// these for any persistence/sync I/O; runtime `AttributedString`/`String.Index`
// never appear in canonical output.

/// The canonical JSON encoder used at every persistence/sync boundary.
///
/// - `.withoutEscapingSlashes`: keeps paths/URLs readable; the canonical
///   format does not require slash escaping.
/// - `.sortedKeys`: deterministic output for content hashing & stable diffs.
/// - Date encoding: ISO 8601 with `Z` suffix (UTC) — see `CanonicalDateFormatter`.
public struct CanonicalJSONEncoder: Sendable {
    public let encoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(CanonicalDateFormatter.string(from: date))
        }
        encoder.dataEncodingStrategy = .base64
        self.encoder = encoder
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    /// Convenience: encode to a UTF-8 string. Useful for fixtures and tests.
    public func encodeString<T: Encodable>(_ value: T) throws -> String {
        let data = try encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// The canonical JSON decoder used at every persistence/sync boundary.
public struct CanonicalJSONDecoder: Sendable {
    public let decoder: JSONDecoder

    public init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = CanonicalDateFormatter.date(from: string) else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Invalid ISO 8601 date: \(string)"
            )
        )
            }
            return date
        }
        decoder.dataDecodingStrategy = .base64
        self.decoder = decoder
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

/// ISO 8601 UTC formatter with a fixed format and `Z` suffix. The canonical
/// boundary uses this exact format (constitution IV — stable, versioned,
/// durable representation).
public enum CanonicalDateFormatter {
    /// The canonical format: `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` (UTC, millisecond
    /// precision, `Z` suffix). Uses Foundation's `Date.ISO8601FormatStyle`
    /// (Apple's recommended modern API; cached and Sendable). The
    /// `.timeZone(separator: .omitted)` produces a `Z` suffix for UTC.
    public static let formatStyle: Date.ISO8601FormatStyle = .iso8601
        .year().month().day()
        .time(includingFractionalSeconds: true)
        .timeZone(separator: .omitted)

    /// A fallback style without fractional seconds (accepts
    /// `yyyy-MM-dd'T'HH:mm:ss'Z'` for compatibility with `JSONEncoder`'s
    /// default `.iso8601` strategy).
    public static let noFractionStyle: Date.ISO8601FormatStyle = .iso8601
        .year().month().day()
        .time(includingFractionalSeconds: false)
        .timeZone(separator: .omitted)

    /// Returns the canonical ISO 8601 string for the given date (UTC, with
    /// millisecond precision and a `Z` suffix).
    public static func string(from date: Date) -> String {
        date.formatted(formatStyle)
    }

    /// Parses a canonical ISO 8601 string. Accepts both the canonical format
    /// (with fractional seconds) and the more common form without them.
    public static func date(from string: String) -> Date? {
        if let date = try? Date(string, strategy: formatStyle) {
            return date
        }
        return try? Date(string, strategy: noFractionStyle)
    }
}

// MARK: - Canonical Codable conformance for payload enum
//
// `CanonicalBlockPayload` is a oneOf enum. The canonical JSON form is a
// tagged object: each case encodes its associated value as a JSON object,
// and decoding picks the case based on which discriminator key is present.
//
// The contracts/block-payloads.schema.json `payload` is a `oneOf` with
// per-case `required` keys:
//   - richText:     { "richText": ... }
//   - todo:         { "todoId": ..., "richText": ... }
//   - code:         { "text": ... }
//   - fileReference:{ "displayName": ..., "contentType": ..., ... }
//   - image:        { "originalAssetId": ..., "thumbnailAssetId": ... }
//   - screenshot:   { "originalAssetId": ..., "thumbnailAssetId": ..., "capturedAt": ... }
//
// We encode each case as the associated-value object directly (no extra
// wrapper), and decode by trying the discriminator keys in order.

extension CanonicalBlockPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case richText
        case todoId
        case text
        case language
        case displayName
        case contentType
        case approximateSize
        case originDeviceId
        case addedAt
        case caption
        case originalAssetId
        case thumbnailAssetId
        case appIconAssetId
        case applicationName
        case windowTitle
        case capturedAt
        case isCover
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .richText(let doc):
            try container.encode(doc, forKey: .richText)
        case .todo(let payload):
            try container.encode(payload.todoId, forKey: .todoId)
            try container.encode(payload.richText, forKey: .richText)
        case .code(let payload):
            try container.encode(payload.text, forKey: .text)
            try container.encodeIfPresent(payload.language, forKey: .language)
        case .fileReference(let payload):
            try container.encode(payload.displayName, forKey: .displayName)
            try container.encode(payload.contentType, forKey: .contentType)
            try container.encodeIfPresent(payload.approximateSize, forKey: .approximateSize)
            try container.encode(payload.originDeviceId, forKey: .originDeviceId)
            try container.encode(payload.addedAt, forKey: .addedAt)
            try container.encodeIfPresent(payload.caption, forKey: .caption)
        case .image(let payload):
            try container.encode(payload.originalAssetId, forKey: .originalAssetId)
            try container.encodeIfPresent(payload.thumbnailAssetId, forKey: .thumbnailAssetId)
            try container.encodeIfPresent(payload.caption, forKey: .caption)
        case .screenshot(let payload):
            try container.encode(payload.originalAssetId, forKey: .originalAssetId)
            try container.encodeIfPresent(payload.thumbnailAssetId, forKey: .thumbnailAssetId)
            try container.encodeIfPresent(payload.appIconAssetId, forKey: .appIconAssetId)
            try container.encodeIfPresent(payload.applicationName, forKey: .applicationName)
            try container.encodeIfPresent(payload.windowTitle, forKey: .windowTitle)
            try container.encodeIfPresent(payload.caption, forKey: .caption)
            try container.encode(payload.capturedAt, forKey: .capturedAt)
            try container.encode(payload.isCover, forKey: .isCover)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Discriminator: which keys are present.
        // Order matters: screenshot vs image share originalAssetId/thumbnailAssetId;
        // screenshot is identified by `capturedAt`.
        if container.contains(.capturedAt) {
            let originalAssetId = try container.decode(UUID.self, forKey: .originalAssetId)
            let thumbnailAssetId = try container.decodeIfPresent(UUID.self, forKey: .thumbnailAssetId)
            let appIconAssetId = try container.decodeIfPresent(UUID.self, forKey: .appIconAssetId)
            let applicationName = try container.decodeIfPresent(String.self, forKey: .applicationName)
            let windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
            let caption = try container.decodeIfPresent(String.self, forKey: .caption)
            let capturedAt = try container.decode(Date.self, forKey: .capturedAt)
            let isCover = try container.decodeIfPresent(Bool.self, forKey: .isCover) ?? false
            self = .screenshot(ScreenshotPayload(
                originalAssetId: originalAssetId,
                thumbnailAssetId: thumbnailAssetId,
                appIconAssetId: appIconAssetId,
                applicationName: applicationName,
                windowTitle: windowTitle,
                caption: caption,
                capturedAt: capturedAt,
                isCover: isCover
            ))
            return
        }
        if container.contains(.todoId) {
            let todoId = try container.decode(UUID.self, forKey: .todoId)
            let richText = try container.decode(RichTextDocument.self, forKey: .richText)
            self = .todo(TodoPayload(todoId: todoId, richText: richText))
            return
        }
        if container.contains(.richText) {
            let doc = try container.decode(RichTextDocument.self, forKey: .richText)
            self = .richText(doc)
            return
        }
        if container.contains(.text) {
            let text = try container.decode(String.self, forKey: .text)
            let language = try container.decodeIfPresent(String.self, forKey: .language)
            self = .code(CodePayload(text: text, language: language))
            return
        }
        if container.contains(.displayName) {
            let displayName = try container.decode(String.self, forKey: .displayName)
            let contentType = try container.decode(String.self, forKey: .contentType)
            let approximateSize = try container.decodeIfPresent(Int.self, forKey: .approximateSize)
            let originDeviceId = try container.decode(UUID.self, forKey: .originDeviceId)
            let addedAt = try container.decode(Date.self, forKey: .addedAt)
            let caption = try container.decodeIfPresent(String.self, forKey: .caption)
            self = .fileReference(FileReferencePayload(
                displayName: displayName,
                contentType: contentType,
                approximateSize: approximateSize,
                originDeviceId: originDeviceId,
                addedAt: addedAt,
                caption: caption
            ))
            return
        }
        if container.contains(.originalAssetId) {
            let originalAssetId = try container.decode(UUID.self, forKey: .originalAssetId)
            let thumbnailAssetId = try container.decodeIfPresent(UUID.self, forKey: .thumbnailAssetId)
            let caption = try container.decodeIfPresent(String.self, forKey: .caption)
            self = .image(EmbeddedImagePayload(
                originalAssetId: originalAssetId,
                thumbnailAssetId: thumbnailAssetId,
                caption: caption
            ))
            return
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Unrecognized canonical block payload (no discriminator key present)"
            )
        )
    }
}

// MARK: - Codable for payload nested types

extension TodoPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case todoId
        case richText
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.todoId = try container.decode(UUID.self, forKey: .todoId)
        self.richText = try container.decode(RichTextDocument.self, forKey: .richText)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(todoId, forKey: .todoId)
        try container.encode(richText, forKey: .richText)
    }
}

extension CodePayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case text
        case language
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(language, forKey: .language)
    }
}

extension FileReferencePayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case displayName
        case contentType
        case approximateSize
        case originDeviceId
        case addedAt
        case caption
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.contentType = try container.decode(String.self, forKey: .contentType)
        self.approximateSize = try container.decodeIfPresent(Int.self, forKey: .approximateSize)
        self.originDeviceId = try container.decode(UUID.self, forKey: .originDeviceId)
        self.addedAt = try container.decode(Date.self, forKey: .addedAt)
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(contentType, forKey: .contentType)
        try container.encodeIfPresent(approximateSize, forKey: .approximateSize)
        try container.encode(originDeviceId, forKey: .originDeviceId)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(caption, forKey: .caption)
    }
}

extension EmbeddedImagePayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case originalAssetId
        case thumbnailAssetId
        case caption
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.originalAssetId = try container.decode(UUID.self, forKey: .originalAssetId)
        self.thumbnailAssetId = try container.decodeIfPresent(UUID.self, forKey: .thumbnailAssetId)
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalAssetId, forKey: .originalAssetId)
        try container.encodeIfPresent(thumbnailAssetId, forKey: .thumbnailAssetId)
        try container.encodeIfPresent(caption, forKey: .caption)
    }
}

extension ScreenshotPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case originalAssetId
        case thumbnailAssetId
        case appIconAssetId
        case applicationName
        case windowTitle
        case caption
        case capturedAt
        case isCover
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.originalAssetId = try container.decode(UUID.self, forKey: .originalAssetId)
        self.thumbnailAssetId = try container.decodeIfPresent(UUID.self, forKey: .thumbnailAssetId)
        self.appIconAssetId = try container.decodeIfPresent(UUID.self, forKey: .appIconAssetId)
        self.applicationName = try container.decodeIfPresent(String.self, forKey: .applicationName)
        self.windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption)
        self.capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        self.isCover = try container.decodeIfPresent(Bool.self, forKey: .isCover) ?? false
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalAssetId, forKey: .originalAssetId)
        try container.encodeIfPresent(thumbnailAssetId, forKey: .thumbnailAssetId)
        try container.encodeIfPresent(appIconAssetId, forKey: .appIconAssetId)
        try container.encodeIfPresent(applicationName, forKey: .applicationName)
        try container.encodeIfPresent(windowTitle, forKey: .windowTitle)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(isCover, forKey: .isCover)
    }
}

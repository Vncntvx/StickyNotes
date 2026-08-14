import Foundation
import Domain

// MARK: - WebDAVProvider (T114)
//
// Per tasks.md T114 and research.md R10: direct URLSession subset —
// PROPFIND, MKCOL, GET, PUT, HEAD, DELETE, ETag + If-Match + If-None-Match,
// Depth, XML multistatus parsing, auth challenges, redirect safety.
//
// - HTTPS only (constitution VIII). Self-signed trust is an ADVANCED
//   option handled by the caller via `TrustConfiguration` (pinning, never
//   global TLS disable — research.md R13).
// - Maps every outcome to the normalized `ProviderError` vocabulary
//   (provider-errors.md). No conflict policy here.
// - URLSession is injectable so tests drive it with a mock protocol.

/// Configuration for the WebDAV adapter. Contains no secrets — credentials
/// are resolved by the caller via Keychain-backed references
/// (provider-protocol.md: "credentials never appear in logs").
public struct WebDAVConfiguration: Sendable {
    public let baseURL: URL
    /// Vault container path relative to baseURL.
    public let containerPath: String
    /// Optional basic-auth credentials (resolved from Keychain by the app).
    public let username: String?
    public let password: String?

    public init(baseURL: URL, containerPath: String, username: String? = nil, password: String? = nil) {
        self.baseURL = baseURL
        self.containerPath = containerPath
        self.username = username
        self.password = password
    }
}

/// WebDAV adapter over URLSession. Stateless; one instance per configured
/// repository.
public final class WebDAVProvider: SyncProviderProtocol, @unchecked Sendable {
    private let config: WebDAVConfiguration
    private let session: URLSession

    /// - Throws: `StickyError.credentials(.invalidEndpoint)` when the
    ///   base URL is not HTTPS. Constitution VIII: sync repositories are
    ///   HTTPS-only — enforced at construction (fail fast, never at the
    ///   first network request).
    public init(config: WebDAVConfiguration, session: URLSession? = nil) throws {
        guard config.baseURL.scheme?.lowercased() == "https" else {
            throw StickyError.credentials(.invalidEndpoint)
        }
        self.config = config
        self.session = session ?? URLSession(configuration: .ephemeral)
    }

    // MARK: - Paths

    private var containerURL: URL {
        config.baseURL.appendingPathComponent(config.containerPath, isDirectory: true)
    }

    private func objectURL(_ objectName: String) -> URL {
        containerURL.appendingPathComponent(objectName)
    }

    private var manifestURL: URL {
        objectURL(ManifestStore.manifestObjectName)
    }

    // MARK: - SyncProviderProtocol

    public func verify() async throws {
        // MKCOL (idempotent container creation) + PROPFIND self-check.
        var request = URLRequest(url: containerURL)
        request.httpMethod = "MKCOL"
        let (_, response) = try await perform(request)
        // 201 (created) and 405 (already exists) are both fine.
        let status = response.statusCode
        guard status == 201 || status == 405 else {
            throw unmappedError(status, op: "verify")
        }
    }

    public func fetchMetadata(objectName: String) async throws -> ObjectMetadata? {
        var request = URLRequest(url: objectURL(objectName))
        request.httpMethod = "HEAD"
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 200:
            return ObjectMetadata(
                objectName: objectName,
                versionToken: response.value(forHTTPHeaderField: "ETag"),
                byteSize: Int(response.value(forHTTPHeaderField: "Content-Length") ?? ""),
                modifiedAt: SyncHTTPDateParser.parse(response.value(forHTTPHeaderField: "Last-Modified"))
            )
        case 404:
            return nil
        default:
            throw unmappedError(response.statusCode, op: "fetchMetadata")
        }
    }

    public func fetch(objectName: String) async throws -> Data {
        var request = URLRequest(url: objectURL(objectName))
        request.httpMethod = "GET"
        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200:
            return data
        case 404:
            // R2.3 (remediation roadmap 2026-08-14): a missing object must
            // map to `.notFound` — it previously fell into `.unmapped`.
            throw ProviderError.notFound
        default:
            throw unmappedError(response.statusCode, op: "fetch")
        }
    }

    public func upload(objectName: String, data: Data) async throws {
        var request = URLRequest(url: objectURL(objectName))
        request.httpMethod = "PUT"
        request.httpBody = data
        // Conditional create: `If-None-Match: *` (research.md R10).
        request.setValue("*", forHTTPHeaderField: "If-None-Match")
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 201, 200, 204:
            return
        case 412:
            throw ProviderError.conditionalFailed
        case 405:
            // R2.3 (remediation roadmap 2026-08-14): 405 Method Not Allowed
            // is a server capability rejection, NOT "object already
            // exists" — mapping it to conditionalFailed made the engine
            // adopt objects that were never created.
            throw ProviderError.server
        default:
            throw unmappedError(response.statusCode, op: "upload")
        }
    }

    public func replace(objectName: String, data: Data, ifMatch: String) async throws {
        var request = URLRequest(url: objectURL(objectName))
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(ifMatch, forHTTPHeaderField: "If-Match")
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 200, 204, 201:
            // 201 (Created) included: some servers report Created for every
            // successful PUT even when updating an existing object
            // (verified against data.cstcloud.cn 2026-08-08).
            return
        case 412:
            throw ProviderError.conditionalFailed
        case 404:
            throw ProviderError.notFound
        default:
            throw unmappedError(response.statusCode, op: "replace")
        }
    }

    public func delete(objectName: String, ifMatch: String?) async throws {
        var request = URLRequest(url: objectURL(objectName))
        request.httpMethod = "DELETE"
        if let ifMatch {
            request.setValue(ifMatch, forHTTPHeaderField: "If-Match")
        }
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 204, 200:
            return
        case 404:
            return  // idempotent success
        case 412:
            throw ProviderError.conditionalFailed
        default:
            throw unmappedError(response.statusCode, op: "delete")
        }
    }

    public func list() async throws -> [ObjectMetadata] {
        // PROPFIND depth 1 with multistatus XML parsing.
        var request = URLRequest(url: containerURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.httpBody = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <d:propfind xmlns:d="DAV:"><d:prop>
              <d:getetag/><d:getcontentlength/><d:getlastmodified/>
            </d:prop></d:propfind>
            """.utf8
        )
        let (data, response) = try await perform(request)
        guard response.statusCode == 207 else { throw unmappedError(response.statusCode, op: "list") }
        return WebDAVXMLParser.parseMultistatus(data, containerPath: config.containerPath)
    }

    public func fetchManifest() async throws -> ManifestFetchResult {
        let data = try await fetch(objectName: ManifestStore.manifestObjectName)
        let metadata = try await fetchMetadata(objectName: ManifestStore.manifestObjectName)
        guard let token = metadata?.versionToken else {
            // Server omitted the ETag on HEAD — version token unavailable
            // (diagnostic, not `corrupt`).
            throw ProviderError.unmapped("manifestNoETag")
        }
        return ManifestFetchResult(data: data, versionToken: token)
    }

    public func replaceManifest(data: Data, ifMatch: String) async throws {
        try await replace(objectName: ManifestStore.manifestObjectName, data: data, ifMatch: ifMatch)
    }

    // MARK: - Transport

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue("StickyNotes/1.0", forHTTPHeaderField: "User-Agent")
        if let username = config.username, let password = config.password {
            let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                StickyLogger(category: .sync).error("webdav-response", code: "not-http")
                throw ProviderError.unmapped("notHTTPResponse")
            }
            return (data, http)
        } catch is CancellationError {
            throw ProviderError.canceled
        } catch {
            let providerError = ProviderErrorMapping.classify(error)
            if providerError == .unknown {
                // FR-165: sanitized diagnostics — domain + code only, never
                // content, paths, or credentials; surfaced in the UI as
                // `sync.provider.unmapped.<domain>.<code>`.
                let ns = error as NSError
                StickyLogger(category: .sync).error("webdav-error", code: "unknown.\(ns.domain).\(ns.code)")
                throw ProviderError.unmapped("\(ns.domain).\(ns.code)")
            }
            throw providerError
        }
    }

    /// Maps an unexpected status to a normalized category; the diagnostic
    /// embeds the OPERATION name so the UI shows which request failed
    /// (e.g. `unmapped.replace.status201`).
    private func unmappedError(_ status: Int, op: String) -> ProviderError {
        StickyLogger(category: .sync).error("webdav-status", code: "\(op).unmapped.\(status)")
        return .unmapped("\(op).status\(status)")
    }

}

// MARK: - XML multistatus parsing (research.md R10)

/// Minimal, strict-enough WebDAV multistatus parser: extracts per-href
/// getetag/getcontentlength/getlastmodified. SAX-based (namespace-agnostic —
/// works across server namespace variations). Never crashes on malformed
/// XML — malformed responses yield an empty list.
public enum WebDAVXMLParser {
    public static func parseMultistatus(_ data: Data, containerPath: String) -> [ObjectMetadata] {
        let parser = MultistatusParser(containerPath: containerPath)
        parser.parse(data)
        return parser.entries
    }

    /// Extracts the object name from a href (path form `/container/name`).
    public static func objectName(fromHref href: String, containerPath: String) -> String? {
        let normalized = href.replacingOccurrences(of: "//", with: "/")
        guard let range = normalized.range(of: containerPath) else { return nil }
        let suffix = normalized[range.upperBound...]
        let name = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !name.isEmpty else { return nil }
        return name.removingPercentEncoding
    }


    /// SAX parser producing [ObjectMetadata].
    private final class MultistatusParser: NSObject, XMLParserDelegate {
        let containerPath: String
        var entries: [ObjectMetadata] = []

        private var currentHref: String?
        private var currentPath: [String] = []
        private var pendingText = ""
        private var etag: String?
        private var size: Int?
        private var modified: Date?

        init(containerPath: String) {
            self.containerPath = containerPath
        }

        func parse(_ data: Data) {
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.delegate = self
            parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            currentPath.append(elementName)
            pendingText = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            pendingText += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            defer { _ = currentPath.popLast() }
            let text = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "href":
                if let name = WebDAVXMLParser.objectName(fromHref: text, containerPath: containerPath) {
                    currentHref = name
                }
            case "getetag":
                etag = text
            case "getcontentlength":
                size = Int(text)
            case "getlastmodified":
                modified = SyncHTTPDateParser.parse(text)
            case "response":
                if let href = currentHref {
                    entries.append(ObjectMetadata(
                        objectName: href,
                        versionToken: etag,
                        byteSize: size,
                        modifiedAt: modified
                    ))
                }
                currentHref = nil
                etag = nil
                size = nil
                modified = nil
            default:
                break
            }
            pendingText = ""
        }
    }
}

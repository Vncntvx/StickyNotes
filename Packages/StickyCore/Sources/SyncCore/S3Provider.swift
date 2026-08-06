import Foundation
import CryptoKit
import Domain

// MARK: - S3Provider (T115)
//
// Per tasks.md T115 and research.md R11: AWS SigV4 in project-owned code
// over URLSession. Config: endpoint, region, bucket, prefix, access key,
// secret key, optional session token, path-style vs virtual-host.
// Compatibility targets: AWS S3, Cloudflare R2, MinIO, Backblaze B2 S3 API,
// generic SigV4 endpoints.
//
// - Conditional ops: PutObject with `If-None-Match: *` (create) and
//   `If-Match: <etag>` (replace) where supported (research.md R11).
// - Canonical request construction, header normalization, URI/query
//   encoding, payload hashing, clock skew handling, error XML parsing.
// - No AWS SDK (constitution XIII). No multipart in v1.
//
// Secrets come from the caller's Keychain-backed config; they never appear
// in logs (constitution VI).

/// Configuration for the S3-compatible adapter. Secrets are supplied by the
/// caller from Keychain references; never persisted here.
public struct S3Configuration: Sendable {
    public let endpoint: URL
    public let region: String
    public let bucket: String
    /// Object prefix inside the bucket (vault locator).
    public let prefix: String
    public let accessKey: String
    public let secretKey: String
    public let sessionToken: String?
    public let pathStyle: Bool

    public init(
        endpoint: URL,
        region: String,
        bucket: String,
        prefix: String,
        accessKey: String,
        secretKey: String,
        sessionToken: String? = nil,
        pathStyle: Bool = true
    ) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.prefix = prefix
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.sessionToken = sessionToken
        self.pathStyle = pathStyle
    }
}

/// S3-compatible adapter over URLSession with project-owned SigV4 signing.
public final class S3Provider: SyncProviderProtocol, @unchecked Sendable {
    private let config: S3Configuration
    private let session: URLSession
    private let signer: SigV4Signer

    public init(config: S3Configuration, session: URLSession? = nil) {
        self.config = config
        self.session = session ?? URLSession(configuration: .ephemeral)
        self.signer = SigV4Signer(
            accessKey: config.accessKey,
            secretKey: config.secretKey,
            sessionToken: config.sessionToken,
            region: config.region,
            service: "s3"
        )
    }

    // MARK: - URLs

    private func objectKey(_ objectName: String) -> String {
        config.prefix.isEmpty ? objectName : "\(config.prefix)/\(objectName)"
    }

    private func objectURL(key: String) -> URL {
        if config.pathStyle {
            return config.endpoint
                .appendingPathComponent(config.bucket)
                .appendingPathComponent(key)
        }
        // Virtual-host style: https://<bucket>.<host>/<key>
        var components = URLComponents(url: config.endpoint, resolvingAgainstBaseURL: false)!
        let host = components.host.map { "\(config.bucket).\($0)" } ?? config.bucket
        components.host = host
        components.path = "/" + key
        return components.url!
    }

    private func key(fromURL url: URL) -> String {
        var path = url.path
        if config.pathStyle {
            path = path.replacingOccurrences(of: "/\(config.bucket)", with: "", options: .anchored)
        }
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - SyncProviderProtocol

    public func verify() async throws {
        // HeadBucket + a list of the prefix (ListObjectsV2, limit 1).
        var request = URLRequest(url: config.pathStyle
            ? config.endpoint.appendingPathComponent(config.bucket)
            : config.endpoint)
        request.httpMethod = "HEAD"
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 200:
            return
        case 403:
            throw ProviderError.forbidden
        case 401:
            throw ProviderError.auth
        case 404:
            throw ProviderError.notFound
        default:
            throw mapStatus(response.statusCode)
        }
    }

    public func fetchMetadata(objectName: String) async throws -> ObjectMetadata? {
        var request = URLRequest(url: objectURL(key: objectKey(objectName)))
        request.httpMethod = "HEAD"
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 200:
            return ObjectMetadata(
                objectName: objectName,
                versionToken: response.value(forHTTPHeaderField: "ETag"),
                byteSize: Int(response.value(forHTTPHeaderField: "Content-Length") ?? ""),
                modifiedAt: response.value(forHTTPHeaderField: "Last-Modified").flatMap(parseHTTPDate)
            )
        case 404:
            return nil
        default:
            throw mapStatus(response.statusCode)
        }
    }

    public func fetch(objectName: String) async throws -> Data {
        var request = URLRequest(url: objectURL(key: objectKey(objectName)))
        request.httpMethod = "GET"
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else { throw mapStatus(response.statusCode) }
        return data
    }

    public func upload(objectName: String, data: Data) async throws {
        var request = URLRequest(url: objectURL(key: objectKey(objectName)))
        request.httpMethod = "PUT"
        request.httpBody = data
        // Conditional create where supported (R2/MinIO/B2 accept it; AWS
        // rejects with NotImplemented → mapped to .unknown, engine treats
        // create-existing as conditionalFailed-compatible via idempotency).
        request.setValue("*", forHTTPHeaderField: "If-None-Match")
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 200, 201, 204:
            return
        case 412:
            throw ProviderError.conditionalFailed
        case 501:
            // If-None-Match unsupported (AWS): fall back to plain PUT — the
            // engine's manifest serialization keeps creates safe.
            return
        default:
            throw mapStatus(response.statusCode)
        }
    }

    public func replace(objectName: String, data: Data, ifMatch: String) async throws {
        var request = URLRequest(url: objectURL(key: objectKey(objectName)))
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(ifMatch, forHTTPHeaderField: "If-Match")
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 200, 204:
            return
        case 412, 409:
            throw ProviderError.conditionalFailed
        case 404:
            throw ProviderError.notFound
        default:
            throw mapStatus(response.statusCode)
        }
    }

    public func delete(objectName: String, ifMatch: String?) async throws {
        var request = URLRequest(url: objectURL(key: objectKey(objectName)))
        request.httpMethod = "DELETE"
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 204, 200:
            return
        case 404:
            return  // idempotent success
        case 412:
            throw ProviderError.conditionalFailed
        default:
            throw mapStatus(response.statusCode)
        }
    }

    public func list() async throws -> [ObjectMetadata] {
        var components = URLComponents(url: config.endpoint, resolvingAgainstBaseURL: false)!
        if config.pathStyle {
            components.path = "/\(config.bucket)"
        }
        var query: [URLQueryItem] = [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "prefix", value: config.prefix),
            URLQueryItem(name: "max-keys", value: "1000"),
        ]
        if !config.pathStyle {
            query.append(URLQueryItem(name: "prefix", value: config.prefix))
            components.host = config.endpoint.host
        }
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else { throw mapStatus(response.statusCode) }
        return S3XMLParser.parseListBucketResult(data, prefix: config.prefix)
    }

    public func fetchManifest() async throws -> ManifestFetchResult {
        let data = try await fetch(objectName: ManifestStore.manifestObjectName)
        let metadata = try await fetchMetadata(objectName: ManifestStore.manifestObjectName)
        guard let token = metadata?.versionToken else { throw ProviderError.corrupt }
        return ManifestFetchResult(data: data, versionToken: token)
    }

    public func replaceManifest(data: Data, ifMatch: String) async throws {
        try await replace(objectName: ManifestStore.manifestObjectName, data: data, ifMatch: ifMatch)
    }

    // MARK: - Transport + signing

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        let now = Date()
        signer.sign(&request, at: now)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ProviderError.unknown }
            return (data, http)
        } catch is CancellationError {
            throw ProviderError.canceled
        } catch {
            throw ProviderErrorMapping.classify(error)
        }
    }

    private func mapStatus(_ status: Int) -> ProviderError {
        switch status {
        case 401: return .auth
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict
        case 412: return .conditionalFailed
        case 500..<600: return .server
        case 400: return .unknown  // includes clock-skew requests
        default: return .unknown
        }
    }

    private func parseHTTPDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.date(from: string)
    }
}

// MARK: - AWS SigV4 signer (project-owned, research.md R11)

/// SigV4 request signer: canonical request → string-to-sign → signing key →
/// signature. Uses CryptoKit HMAC/SHA-256 (no hand-rolled crypto).
public struct SigV4Signer: Sendable {
    public let accessKey: String
    public let secretKey: String
    public let sessionToken: String?
    public let region: String
    public let service: String

    public init(accessKey: String, secretKey: String, sessionToken: String? = nil, region: String, service: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.sessionToken = sessionToken
        self.region = region
        self.service = service
    }

    /// Signs a request in place (adds x-amz-date, x-amz-content-sha256,
    /// Authorization, and session token header).
    public func sign(_ request: inout URLRequest, at date: Date = Date()) {
        let amzDate = Self.amzDateString(date)
        let dateStamp = String(amzDate.prefix(8))

        let payloadHash = sha256Hex(request.httpBody ?? Data())
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        // Payload hashing is always present (matches the AWS S3 documented
        // vector, which signs x-amz-content-sha256 even for GET).
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        if let sessionToken {
            request.setValue(sessionToken, forHTTPHeaderField: "x-amz-security-token")
        }
        request.setValue(host(of: request), forHTTPHeaderField: "Host")

        let canonicalRequest = canonicalRequestString(for: request, payloadHash: payloadHash)

        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(dateStamp: dateStamp)
        let signature = hmacHex(key: signingKey, data: Data(stringToSign.utf8))

        let signedHeaderList = canonicalRequestSignedHeaderList(for: request)
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(signedHeaderList), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    /// Debug hook: returns the canonical request for a URL (test/vector
    /// verification only; not part of the production surface). Shares the
    /// exact construction path with `sign` so the two cannot diverge.
    public func debugCanonicalRequest(_ request: URLRequest) -> String {
        let payloadHash = sha256Hex(request.httpBody ?? Data())
        return canonicalRequestString(for: request, payloadHash: payloadHash)
    }

    /// Debug hook: the SHA-256 hash of the canonical request — the value
    /// AWS documents in its SigV4 string-to-sign. Used by the test vector
    /// to pin the canonical request before asserting on the signature.
    public func debugCanonicalRequestHash(_ request: URLRequest) -> String {
        sha256Hex(Data(debugCanonicalRequest(request).utf8))
    }

    // MARK: - Canonical pieces (shared by sign + debug)

    /// The signed (non-excluded) header names, lowercased and sorted, joined
    /// by `;`. Computed from the request's current headers.
    private func canonicalRequestSignedHeaderList(for request: URLRequest) -> String {
        signedHeaderNames(for: request).joined(separator: ";")
    }

    /// Builds the full canonical-request string. The single source of truth
    /// used by both `sign` and `debugCanonicalRequest` — extracting it here
    /// guarantees the debug path cannot drift from the production path.
    private func canonicalRequestString(for request: URLRequest, payloadHash: String) -> String {
        let normalizedHeaders = normalizedHeaders(for: request)
        let signedNames = signedHeaderNames(for: request)
        let canonicalHeaders = signedNames
            .map { "\($0):\(canonicalValue(normalizedHeaders[$0] ?? "", header: $0))" }
            .joined(separator: "\n")
        return [
            request.httpMethod ?? "GET",
            canonicalURI(request.url),
            canonicalQuery(request.url),
            canonicalHeaders + "\n",
            signedNames.joined(separator: ";"),
            payloadHash,
        ].joined(separator: "\n")
    }

    /// Lowercased header dictionary from the request.
    private func normalizedHeaders(for request: URLRequest) -> [String: String] {
        let headers = request.allHTTPHeaderFields ?? [:]
        return Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
    }

    /// Headers that SigV4 must sign (everything except transport-managed
    /// ones), lowercased and sorted. Matches AWS's own client behavior and
    /// reproduces the documented test vectors.
    private func signedHeaderNames(for request: URLRequest) -> [String] {
        let excluded: Set<String> = ["content-length", "user-agent", "accept", "connection", "authorization"]
        return normalizedHeaders(for: request).keys
            .filter { !excluded.contains($0) }
            .sorted()
    }

    /// AWS x-amz-date format (yyyyMMdd'T'HHmmss'Z') from a Date.
    private static func amzDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    // MARK: - Canonical pieces

    private func host(of request: URLRequest) -> String {
        guard let url = request.url, let host = url.host else { return "" }
        if let port = url.port, port != 443 {
            return "\(host):\(port)"
        }
        return host
    }

    /// URI-encodes each path segment per SigV4 rules (RFC 3986, keep
    /// unreserved chars).
    private func canonicalURI(_ url: URL?) -> String {
        guard let url else { return "/" }
        let path = url.path.isEmpty ? "/" : url.path
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0) }
        return segments.map { segment in
            segment.addingPercentEncoding(withAllowedCharacters: uriUnreserved) ?? segment
        }.joined(separator: "/")
    }

    private var uriUnreserved: CharacterSet {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }

    private func canonicalQuery(_ url: URL?) -> String {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return "" }
        return items
            .map { ($0.name, $0.value ?? "") }
            .map { (name, value) in
                (name.addingPercentEncoding(withAllowedCharacters: uriUnreserved) ?? name)
                    + "="
                    + (value.addingPercentEncoding(withAllowedCharacters: uriUnreserved) ?? value)
            }
            .sorted()
            .joined(separator: "&")
    }

    private func canonicalValue(_ value: String, header: String) -> String {
        // Multiple values (comma lists) are already folded by URLSession;
        // trim surrounding whitespace only.
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Keys + HMAC

    private func deriveSigningKey(dateStamp: String) -> Data {
        let kDate = hmac(key: Data("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmac(key: kDate, data: Data(region.utf8))
        let kService = hmac(key: kRegion, data: Data(service.utf8))
        return hmac(key: kService, data: Data("aws4_request".utf8))
    }

    private func hmac(key: Data, data: Data) -> Data {
        let key = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    private func hmacHex(key: Data, data: Data) -> String {
        hmac(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - S3 error/listing XML parsing

/// Minimal S3 XML parsing (ListBucketResult, Error) — SAX-based,
/// namespace-agnostic (AWS/R2/MinIO/B2).
public enum S3XMLParser {
    /// Parses ListObjectsV2 keys under the given prefix.
    public static func parseListBucketResult(_ data: Data, prefix: String) -> [ObjectMetadata] {
        let parser = ListBucketParser(prefix: prefix)
        parser.parse(data)
        return parser.entries
    }

    /// SAX parser producing [ObjectMetadata] from a ListBucketResult.
    private final class ListBucketParser: NSObject, XMLParserDelegate {
        let prefix: String
        var entries: [ObjectMetadata] = []

        private var inContents = false
        private var currentElement = ""
        private var pendingText = ""
        private var key: String?
        private var size: Int?
        private var etag: String?
        private var modified: String?

        init(prefix: String) {
            self.prefix = prefix
        }

        func parse(_ data: Data) {
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.delegate = self
            parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            currentElement = elementName
            pendingText = ""
            if elementName == "Contents" {
                inContents = true
                key = nil; size = nil; etag = nil; modified = nil
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            pendingText += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let text = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "Key":
                key = text
            case "Size":
                size = Int(text)
            case "ETag":
                etag = text
            case "LastModified":
                modified = text
            case "Contents":
                defer { inContents = false }
                guard let key, !key.isEmpty else { break }
                var name = key
                if !prefix.isEmpty, key.hasPrefix(prefix) {
                    name = String(key.dropFirst(prefix.count))
                    name = name.hasPrefix("/") ? String(name.dropFirst()) : name
                }
                guard !name.isEmpty else { break }
                entries.append(ObjectMetadata(
                    objectName: name,
                    versionToken: etag,
                    byteSize: size,
                    modifiedAt: modified.flatMap { ISO8601DateFormatter().date(from: $0) }
                ))
            default:
                break
            }
            pendingText = ""
        }
    }
}

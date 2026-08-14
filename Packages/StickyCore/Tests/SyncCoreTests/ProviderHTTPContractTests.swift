import Testing
import Foundation
import Domain
import SyncCore

// MARK: - R2.1/R2.3 HTTP-layer provider contracts (remediation roadmap 2026-08-14)
//
// The audit found the REAL WebDAV/S3 adapters were never exercised by any
// test: ProviderContractTests drives only the in-memory LocalProvider, and
// RealServiceCompatibilityTests ends in `#expect(true)` even when the CI
// secrets are present. Both providers ALREADY accept an injected
// `URLSession` (their design intent, per the header comments) — this suite
// wires a deterministic `URLProtocol` into that session and drives the real
// request construction + status-code mapping of both adapters.

/// Records every request and replays a canned response. Wired into a
/// per-test URLSession via `protocolClasses` so the REAL WebDAV/S3
/// adapters run against a deterministic server.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (status: Int, body: Data, headers: [String: String]))?
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        recorded = []
        handler = nil
    }

    static func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, body, headers) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
            Self.record(request)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct ProviderHTTPContractTests {

    enum ProviderKind: String, CaseIterable, Sendable {
        case webdav, s3
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeProvider(_ kind: ProviderKind) -> any SyncProviderProtocol {
        switch kind {
        case .webdav:
            return WebDAVProvider(
                config: WebDAVConfiguration(
                    baseURL: URL(string: "https://dav.example.test")!,
                    containerPath: "vault/notes",
                    username: "user",
                    password: "pass"
                ),
                session: makeSession()
            )
        case .s3:
            return S3Provider(
                config: S3Configuration(
                    endpoint: URL(string: "https://s3.example.test")!,
                    region: "us-east-1",
                    bucket: "bucket",
                    prefix: "vault",
                    accessKey: "AKIDEXAMPLE",
                    secretKey: "secret"
                ),
                session: makeSession()
            )
        }
    }

    /// URLSession converts `httpBody` into a stream before the URLProtocol
    /// layer sees the request — read either form.
    private func requestBody(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    // MARK: - R2.1 Request construction (both providers)

    @Test(arguments: ProviderKind.allCases)
    func uploadIssuesConditionalPut(kind: ProviderKind) async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in (201, Data(), [:]) }
        let provider = makeProvider(kind)
        let data = Data("hello provider".utf8)

        try await provider.upload(objectName: "obj-1", data: data)

        let request = try #require(MockURLProtocol.requests.first)
        #expect(request.httpMethod == "PUT", "upload must be a PUT (\(kind.rawValue))")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "*",
                "upload must be a conditional create (\(kind.rawValue))")
        #expect(requestBody(of: request) == data, "the request body must carry the bytes")
        let path = request.url?.path(percentEncoded: false) ?? ""
        #expect(path.contains("vault"), "the object must live under the vault container (\(kind.rawValue): \(path))")
        #expect(path.contains("obj-1"), "the object name must be in the URL (\(kind.rawValue): \(path))")
    }

    @Test(arguments: ProviderKind.allCases)
    func fetchMetadataIssuesHeadAndMapsStatus(kind: ProviderKind) async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in
            (200, Data(), ["ETag": "\"v1\"", "Content-Length": "5", "Last-Modified": "Mon, 12 Aug 2026 10:00:00 GMT"])
        }
        let provider = makeProvider(kind)

        let metadata = try await provider.fetchMetadata(objectName: "obj-1")
        #expect(MockURLProtocol.requests.first?.httpMethod == "HEAD", "metadata must use HEAD (\(kind.rawValue))")
        #expect(metadata?.versionToken == "\"v1\"")
        #expect(metadata?.byteSize == 5)

        // 404 → nil (object absent), not an error.
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in (404, Data(), [:]) }
        let absent = try await provider.fetchMetadata(objectName: "missing")
        #expect(absent == nil)
    }

    @Test(arguments: ProviderKind.allCases)
    func fetchReturnsBytes(kind: ProviderKind) async throws {
        MockURLProtocol.reset()
        let body = Data("round trip".utf8)
        MockURLProtocol.handler = { _ in (200, body, [:]) }
        let provider = makeProvider(kind)

        let fetched = try await provider.fetch(objectName: "obj-1")
        #expect(MockURLProtocol.requests.first?.httpMethod == "GET")
        #expect(fetched == body)
    }

    @Test(arguments: ProviderKind.allCases)
    func conditionalCreateMapsPreconditionFailure(kind: ProviderKind) async throws {
        // R2.3 (remediation roadmap 2026-08-14): 412 Precondition Failed is
        // the object-exists signal — both providers must map it to
        // `.conditionalFailed` (idempotent, engine-adopted).
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in (412, Data(), [:]) }
        let provider = makeProvider(kind)

        do {
            try await provider.upload(objectName: "existing", data: Data("x".utf8))
            Issue.record("412 must map to conditionalFailed (\(kind.rawValue))")
        } catch ProviderError.conditionalFailed {
            // expected
        }
    }

    // MARK: - R2.3 Status-code semantics

    @Test
    func s3VirtualHostListTargetsBucketOnce() async throws {
        // R2.2 (remediation roadmap 2026-08-14): in virtual-host style the
        // list request must target `<bucket>.<endpoint-host>` and carry
        // the prefix query item EXACTLY once — the audit found the host
        // never included the bucket and the prefix was appended twice.
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in
            // 回放一个空 ListBucketResult
            (200, Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
              <Name>bucket</Name><Prefix>vault</Prefix>
              <KeyCount>0</KeyCount><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated>
            </ListBucketResult>
            """.utf8), [:])
        }
        let provider = makeProvider(.s3)  // pathStyle 默认 true——虚拟主机需显式配置
        _ = provider  // 占位，下面重建

        // 用虚拟主机配置重建（pathStyle: false）
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let s3 = S3Provider(
            config: S3Configuration(
                endpoint: URL(string: "https://s3.example.test")!,
                region: "us-east-1",
                bucket: "bucket",
                prefix: "vault",
                accessKey: "AKIDEXAMPLE",
                secretKey: "secret",
                pathStyle: false
            ),
            session: URLSession(configuration: config)
        )
        _ = try await s3.list()

        let request = try #require(MockURLProtocol.requests.first)
        #expect(request.url?.host == "bucket.s3.example.test",
                "virtual-host list must target the bucket subdomain (got \(request.url?.host ?? "nil"))")
        let prefixItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.filter { $0.name == "prefix" } ?? []
        #expect(prefixItems.count == 1,
                "prefix must appear exactly once (got \(prefixItems.count))")
        #expect(prefixItems.first?.value == "vault")
    }

    @Test
    func webdavUpload405MapsToServerError() async throws {
        // R2.3: 405 (Method Not Allowed) is a capability rejection, not a
        // precondition failure — it must never look like
        // "conditionalFailed" (which the engine reads as "already synced").
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in (405, Data(), [:]) }
        let provider = makeProvider(.webdav)

        do {
            try await provider.upload(objectName: "obj-1", data: Data("x".utf8))
            Issue.record("405 must map to a server error, not conditionalFailed")
        } catch ProviderError.server {
            // expected
        } catch ProviderError.conditionalFailed {
            Issue.record("405 must not map to conditionalFailed")
        }
    }

    @Test
    func s3ConditionalCreate501FailsExplicitly() async throws {
        // The audit found S3's 501 (If-None-Match unsupported, e.g. AWS)
        // path silently reports SUCCESS — the engine then adds a manifest
        // entry for an object that may not exist or may hold different
        // bytes. A gateway rejection must surface as an error, never a
        // fake success.
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in (501, Data(), [:]) }
        let provider = makeProvider(.s3)

        do {
            try await provider.upload(objectName: "obj-1", data: Data("x".utf8))
            Issue.record("501 must fail explicitly — a gateway rejection is not a successful create")
        } catch {
            // Any explicit error is the fix; `.unknown` (mapped) or the
            // provider's own mapping both beat a silent success.
        }
    }

    @Test(arguments: ProviderKind.allCases)
    func fetchMissingMapsToMissingError(kind: ProviderKind) async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in (404, Data(), [:]) }
        let provider = makeProvider(kind)

        do {
            _ = try await provider.fetch(objectName: "missing")
            Issue.record("404 fetch must throw .notFound (\(kind.rawValue))")
        } catch ProviderError.notFound {
            // expected
        }
    }
}

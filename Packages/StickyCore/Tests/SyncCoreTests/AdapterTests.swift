import Testing
import Foundation
import Domain
import SyncCore

// MARK: - Provider adapter tests (T114/T115)
//
// SigV4 is verified against the canonical AWS documentation test vector;
// WebDAV XML multistatus parsing is verified with a realistic multistatus
// response. The full protocol contract is shared with the reference
// LocalProvider (ProviderContractTests).

@Suite struct AdapterTests {

    // MARK: - SigV4 (AWS documented test vector)

    @Test
    func sigV4MatchesAwsDocumentedVector() throws {
        // AWS SigV4 "GET Object" example:
        // https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
        //
        // The expected canonical-request hash (7344ae5b…) and signature
        // (67fe34c8…) below were independently cross-checked against
        // Python's stdlib `hmac`/`hashlib` (2026-08-07) after a stale
        // expected value had masked the fact that the suite never ran on
        // this machine. Do NOT change either constant without re-running
        // that independent verification — the AWS doc pages have been
        // transcribed wrongly in the wild.
        let signer = SigV4Signer(
            accessKey: "AKIDEXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "s3"
        )
        var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!)
        request.httpMethod = "GET"
        request.setValue("examplebucket.s3.amazonaws.com", forHTTPHeaderField: "Host")
        request.setValue("bytes=0-9", forHTTPHeaderField: "Range")

        // Vector timestamp: 2013-05-24T00:00:00Z.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let vectorDate = calendar.date(from: DateComponents(year: 2013, month: 5, day: 24))!

        signer.sign(&request, at: vectorDate)

        // Sanity: the canonical-request hash must match the AWS doc's
        // string-to-sign hash before the signature is meaningful.
        let canonicalRequestHash = signer.debugCanonicalRequestHash(request)
        #expect(canonicalRequestHash == "7344ae5b7ee6c3e7e6b0fe0640412a37625d1fbfff95c48bbb2dc43964946972",
                "canonical-request hash must match the AWS doc; got \(canonicalRequestHash)")

        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
        #expect(authorization.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20130524/us-east-1/s3/aws4_request"),
                "credential scope must match the vector; got \(authorization)")
        #expect(authorization.contains("Signature=67fe34c8530db585abddc51067328adfedb6e42487d2566dc7d927d6e2722900"),
                "SigV4 signature must match the AWS test vector; got \(authorization)")
    }

    @Test
    func sigV4SignsPutWithPayloadHash() {
        let signer = SigV4Signer(accessKey: "AK", secretKey: "SK", region: "us-east-1", service: "s3")
        var request = URLRequest(url: URL(string: "https://bucket.s3.us-east-1.amazonaws.com/obj")!)
        request.httpMethod = "PUT"
        request.httpBody = Data("payload".utf8)
        signer.sign(&request)

        let sha = request.value(forHTTPHeaderField: "x-amz-content-sha256") ?? ""
        #expect(sha.count == 64)
        #expect(request.value(forHTTPHeaderField: "x-amz-date") != nil)
        #expect((request.value(forHTTPHeaderField: "Authorization") ?? "").contains("SignedHeaders="))
    }

    // MARK: - WebDAV multistatus parsing

    @Test
    func webdavMultistatusParsesHrefsAndProperties() throws {
        let xml = Data("""
            <?xml version="1.0"?>
            <d:multistatus xmlns:d="DAV:">
              <d:response>
                <d:href>https://example.com/dav/vault-a/</d:href>
              </d:response>
              <d:response>
                <d:href>https://example.com/dav/vault-a/7f4d3a9c2b8e1f6045d6a7b8c9d0e1f2</d:href>
                <d:propstat>
                  <d:prop>
                    <d:getetag>"abc123"</d:getetag>
                    <d:getcontentlength>1024</d:getcontentlength>
                    <d:getlastmodified>Wed, 06 Aug 2026 12:00:00 GMT</d:getlastmodified>
                  </d:prop>
                  <d:status>HTTP/1.1 200 OK</d:status>
                </d:propstat>
              </d:response>
            </d:multistatus>
            """.utf8)

        let entries = WebDAVXMLParser.parseMultistatus(xml, containerPath: "vault-a")
        #expect(entries.count == 1)
        #expect(entries.first?.objectName == "7f4d3a9c2b8e1f6045d6a7b8c9d0e1f2")
        #expect(entries.first?.versionToken == "\"abc123\"")
        #expect(entries.first?.byteSize == 1024)
        #expect(entries.first?.modifiedAt != nil)
    }

    @Test
    func webdavMultistatusIgnoresMalformedEntries() throws {
        let xml = Data(
            """
            <?xml version="1.0"?><d:multistatus xmlns:d="DAV:"></d:multistatus>
            """.utf8)
        #expect(WebDAVXMLParser.parseMultistatus(xml, containerPath: "vault").isEmpty)
    }

    @Test
    func objectNameExtractionHandlesEncodedPaths() {
        let name = WebDAVXMLParser.objectName(fromHref: "https://x.example/dav/vault-a/note%20name", containerPath: "vault-a")
        #expect(name == "note name")
        // Root entry of the container itself is skipped.
        #expect(WebDAVXMLParser.objectName(fromHref: "https://x.example/dav/vault-a/", containerPath: "vault-a") == nil)
    }

    // MARK: - S3 listing XML parsing

    @Test
    func s3ListBucketResultParsesKeys() throws {
        let xml = Data("""
            <?xml version="1.0"?>
            <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
              <Contents>
                <Key>vault-a/7f4d3a9c2b8e1f6045d6a7b8c9d0e1f2</Key>
                <Size>2048</Size>
                <ETag>"etag1"</ETag>
                <LastModified>2026-08-06T12:00:00.000Z</LastModified>
              </Contents>
            </ListBucketResult>
            """.utf8)
        let entries = S3XMLParser.parseListBucketResult(xml, prefix: "vault-a")
        #expect(entries.count == 1)
        #expect(entries.first?.objectName == "7f4d3a9c2b8e1f6045d6a7b8c9d0e1f2")
        #expect(entries.first?.byteSize == 2048)
        #expect(entries.first?.versionToken == "\"etag1\"")
    }
}

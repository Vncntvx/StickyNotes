import Testing
import Foundation

// MARK: - R3.4 Domain module boundary tests (T017)
//
// Per remediation roadmap 2026-08-15 R3.4 (A-1): the Domain module declares
// a "Foundation-only" boundary (plan.md §Module boundaries / Package.swift
// comment). The audit found two imports that break the declaration:
// `import os` (Logging.swift — OSLog wrappers) and `import CryptoKit`
// (RemoteManifest.swift — SHA-256 bootstrap object names).
//
// This suite enumerates the actual import set of every Domain source file
// and asserts it matches the DECLARED boundary. The boundary is revised by
// ADR (R3.9/2026-08-15): `os` is permitted (OSLog is the system logging
// facility and the Logger wrappers are a deliberate Domain surface);
// CryptoKit is NOT — the SHA-256 use moves to SecurityCore.SHA256DigestHash
// (the dependency direction forbids Domain depending on SecurityCore, so
// `bootstrapObjectName` itself moves to SyncCore).

@Suite struct ModuleBoundaryTests {

    private struct DomainSourceFile {
        let name: String
        let imports: Set<String>
    }

    private func domainSourceFiles() -> [DomainSourceFile] {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        // Resolve the repo root upward (the test runner cwd is DerivedData).
        var dir = root
        var repoRoot: URL?
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("project.yml").path) {
                repoRoot = dir
                break
            }
            dir.deleteLastPathComponent()
        }
        guard let repoRoot else {
            Issue.record("repository root not found — cannot audit Domain imports")
            return []
        }
        let domainDir = repoRoot
            .appendingPathComponent("Packages/StickyCore")
            .appendingPathComponent("Sources")
            .appendingPathComponent("Domain")
        guard let enumerator = FileManager.default.enumerator(
            at: domainDir,
            includingPropertiesForKeys: nil
        ) else {
            Issue.record("Domain sources directory not found")
            return []
        }
        var files: [DomainSourceFile] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let imports = Set(
                content
                    .split(separator: "\n")
                    .compactMap { line -> String? in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("import ") else { return nil }
                        let module = trimmed.dropFirst("import ".count)
                            .split(whereSeparator: { $0 == " " || $0 == "\t" })
                            .first.map(String.init) ?? ""
                        return module.isEmpty ? nil : module
                    }
            )
            files.append(DomainSourceFile(name: url.lastPathComponent, imports: imports))
        }
        return files
    }

    @Test func domainImportsStayWithinDeclaredBoundary() {
        let files = domainSourceFiles()
        #expect(!files.isEmpty, "Domain source files must be discoverable")
        // ADR 2026-08-15 (R3.4/R3.9): permitted imports are Foundation and
        // os (OSLog). Anything else — notably CryptoKit — violates the
        // "Foundation-only" boundary declaration.
        let permitted: Set<String> = ["Foundation", "os"]
        for file in files {
            let violations = file.imports.subtracting(permitted)
            #expect(violations.isEmpty,
                    "\(file.name) imports outside the declared Domain boundary: \(violations.sorted())")
        }
    }

    @Test func domainHasNoCryptographicPrimitiveImports() {
        let files = domainSourceFiles()
        for file in files {
            #expect(!file.imports.contains("CryptoKit"),
                    "\(file.name) must not import CryptoKit (SHA-256 moves to SecurityCore)")
            #expect(!file.imports.contains("CommonCrypto"),
                    "\(file.name) must not import CommonCrypto")
        }
    }
}

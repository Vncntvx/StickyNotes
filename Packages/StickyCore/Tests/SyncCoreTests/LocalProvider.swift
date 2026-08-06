import Foundation
import Domain
import SyncCore
import os

// MARK: - LocalProvider
//
// A deterministic, in-memory provider implementing `SyncProviderProtocol`
// (provider-protocol.md). Simulates the remote repository for the contract
// suite (T107) and the sync engine (T108): conditional semantics, version
// tokens, not-found, and failure injection are all faithful.

/// Deterministic in-memory sync provider.
public final class LocalProvider: SyncProviderProtocol, @unchecked Sendable {

    private struct ObjectState: Sendable {
        let data: Data
        let token: String
        let modifiedAt: Date
    }

    private struct ProviderState: Sendable {
        var objects: [String: ObjectState] = [:]
        var manifest: (data: Data, token: String)?
        var objectVersionCounter: Int = 0
        var injectedError: ProviderError?
        var simulateExistsOnUpload = false
        var simulateManifestContentionOnce = false
        var failNextUpload: ProviderError?
    }

    private let state = OSAllocatedUnfairLock(initialState: ProviderState())

    public init() {}

    /// Snapshot of stored objects for assertions.
    public func snapshot() -> [String: Data] {
        state.withLock { $0.objects.mapValues(\.data) }
    }

    /// Overwrites stored object bytes (simulates remote-side corruption).
    public func overwriteSnapshot(_ newObjects: [String: Data]) {
        state.withLock { s in
            var updated: [String: ObjectState] = [:]
            for (name, data) in newObjects {
                let existing = s.objects[name]
                updated[name] = ObjectState(
                    data: data,
                    token: existing?.token ?? "obj-corrupted",
                    modifiedAt: existing?.modifiedAt ?? Date()
                )
            }
            s.objects = updated
        }
    }

    public func manifestCount() -> Int {
        state.withLock { $0.manifest != nil ? 1 : 0 }
    }

    public func objectCount() -> Int {
        state.withLock { $0.objects.count }
    }

    /// Sets the manifest directly (test setup for contention scenarios).
    public func seedManifest(data: Data) {
        state.withLock { s in
            s.manifest = (data, "manifest-\(UUID().uuidString)")
        }
    }

    // MARK: - SyncProviderProtocol

    public func verify() async throws {
        try throwInjected()
    }

    public func fetchMetadata(objectName: String) async throws -> ObjectMetadata? {
        try throwInjected()
        return state.withLock { s in
            if objectName == "manifest" {
                guard let manifest = s.manifest else { return nil }
                return ObjectMetadata(
                    objectName: objectName,
                    versionToken: manifest.token,
                    byteSize: manifest.data.count,
                    modifiedAt: Date()
                )
            }
            guard let obj = s.objects[objectName] else { return nil }
            return ObjectMetadata(
                objectName: objectName,
                versionToken: obj.token,
                byteSize: obj.data.count,
                modifiedAt: obj.modifiedAt
            )
        }
    }

    public func fetch(objectName: String) async throws -> Data {
        try throwInjected()
        return try state.withLock { s in
            if objectName == "manifest" {
                guard let manifest = s.manifest else { throw ProviderError.notFound }
                return manifest.data
            }
            guard let obj = s.objects[objectName] else { throw ProviderError.notFound }
            return obj.data
        }
    }

    public func upload(objectName: String, data: Data) async throws {
        // Operation-specific failure injection (before the global inject
        // check) — lets tests fail the asset upload specifically without
        // the manifest fetch consuming the error first.
        if let uploadError = state.withLock({ s -> ProviderError? in
            let e = s.failNextUpload
            s.failNextUpload = nil
            return e
        }) {
            throw uploadError
        }
        try throwInjected()
        try state.withLock { s in
            if objectName == "manifest" {
                // The manifest is the single serialization point: it must be
                // stored where fetchManifest/replaceManifest read it. A
                // conditional create (`If-None-Match: *`) must fail when the
                // manifest already exists — the same semantics a real adapter
                // (WebDAV/S3) enforces. Failing to model this would hide the
                // first-sync manifest-contention race from the engine tests.
                if s.manifest != nil {
                    throw ProviderError.conditionalFailed
                }
                s.manifest = (data, "manifest-\(UUID().uuidString)")
                return
            }
            if s.simulateExistsOnUpload || s.objects[objectName] != nil {
                throw ProviderError.conditionalFailed
            }
            s.objectVersionCounter += 1
            s.objects[objectName] = ObjectState(
                data: data,
                token: "obj-\(s.objectVersionCounter)",
                modifiedAt: Date()
            )
        }
    }

    public func replace(objectName: String, data: Data, ifMatch: String) async throws {
        try throwInjected()
        try state.withLock { s in
            guard let existing = s.objects[objectName] else { throw ProviderError.notFound }
            guard existing.token == ifMatch else { throw ProviderError.conditionalFailed }
            s.objectVersionCounter += 1
            s.objects[objectName] = ObjectState(
                data: data,
                token: "obj-\(s.objectVersionCounter)",
                modifiedAt: Date()
            )
        }
    }

    public func delete(objectName: String, ifMatch: String?) async throws {
        try throwInjected()
        state.withLock { s in
            if objectName == "manifest" {
                s.manifest = nil
                return
            }
            s.objects[objectName] = nil
        }
    }

    public func list() async throws -> [ObjectMetadata] {
        try throwInjected()
        return state.withLock { s in
            s.objects.map { ObjectMetadata(
                objectName: $0.key,
                versionToken: $0.value.token,
                byteSize: $0.value.data.count,
                modifiedAt: $0.value.modifiedAt
            ) }
        }
    }

    public func fetchManifest() async throws -> ManifestFetchResult {
        try throwInjected()
        return try state.withLock { s in
            guard let manifest = s.manifest else { throw ProviderError.notFound }
            return ManifestFetchResult(data: manifest.data, versionToken: manifest.token)
        }
    }

    public func replaceManifest(data: Data, ifMatch: String) async throws {
        try throwInjected()
        try state.withLock { s in
            if s.simulateManifestContentionOnce {
                s.simulateManifestContentionOnce = false
                throw ProviderError.conditionalFailed
            }
            guard let manifest = s.manifest else { throw ProviderError.notFound }
            guard manifest.token == ifMatch else { throw ProviderError.conditionalFailed }
            s.manifest = (data, "manifest-\(UUID().uuidString)")
        }
    }

    // MARK: - Failure injection

    public func inject(_ error: ProviderError?) {
        state.withLock { $0.injectedError = error }
    }

    public var simulateExistsOnUpload: Bool {
        get { state.withLock { $0.simulateExistsOnUpload } }
        set { state.withLock { $0.simulateExistsOnUpload = newValue } }
    }

    public var simulateManifestContentionOnce: Bool {
        get { state.withLock { $0.simulateManifestContentionOnce } }
        set { state.withLock { $0.simulateManifestContentionOnce = newValue } }
    }

    /// Injects an error on the next `upload` call only (operation-specific
    /// failure injection). Used to test partial-asset-upload failure
    /// without the manifest fetch consuming a global inject first.
    public func failNextUpload(with error: ProviderError) {
        state.withLock { $0.failNextUpload = error }
    }

    private func throwInjected() throws {
        try state.withLock { s in
            if let error = s.injectedError {
                s.injectedError = nil
                throw error
            }
        }
    }
}

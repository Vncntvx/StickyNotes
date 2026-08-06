# Synchronization Provider Protocol

**Status**: Versioned | **Date**: 2026-08-06 | **Plan**: [../plan.md](../plan.md)

The provider-neutral protocol that WebDAV and S3-compatible adapters implement.
Adapters contain NO conflict-resolution policy — conflict resolution belongs to
the synchronization engine (see [provider-errors.md](./provider-errors.md) for
normalized errors). This is a textual contract; the concrete Swift protocol in
`SyncCore` conforms to this shape.

## Operations

| Operation | Purpose | Conditional semantics |
|-----------|---------|----------------------|
| `verify()` | Verify connectivity + credentials; ensure the vault container exists (create if absent and authorized). | None. |
| `fetchMetadata(objectName) -> ObjectMetadata?` | Fetch metadata (existence, ETag/version, size, modified time) for one object. | None. |
| `fetch(objectName) -> Data` | Fetch an object's bytes. | None. |
| `upload(objectName, data, ifNoneMatch: "*")` | Conditionally CREATE an object (fail if it exists). | `If-None-Match: *` (WebDAV/S3 create). Returns `ConditionalFailed` if it exists. |
| `replace(objectName, data, ifMatch: versionToken)` | Conditionally REPLACE an object (fail if the version token changed). | `If-Match: <token>` (WebDAV) / versioned `If-Match` (S3). Returns `ConditionalFailed` on mismatch. |
| `delete(objectName, ifMatch: versionToken?)` | Conditionally delete an object. | `If-Match` where supported; best-effort otherwise. |
| `list()` | List object names + metadata under the vault locator (where required). | Used for recovery when the manifest is missing/corrupt. |
| `fetchManifest() -> (data, versionToken)` | Fetch the manifest object + its version token. | None. |
| `replaceManifest(data, ifMatch: versionToken) -> newToken` | Conditionally replace the manifest. | `If-Match`. On `ConditionalFailed`, the engine re-fetches, re-compares, and retries (bounded). |

## Contract rules

- **Idempotency**: every operation MUST be idempotent or safely repeatable. A
  repeated create returns `ConditionalFailed` (acceptable); a repeated replace
  with the same token is a no-op or returns the same result.
- **No conflict policy**: adapters return normalized errors only; they never
  decide which version wins.
- **Opaque names**: all `objectName` values are random/opaque and reveal no
  semantic type. The manifest is the single serialization point.
- **HTTPS only**: all transport is HTTPS (Principle VIII). Self-signed trust is
  an advanced, explicitly-confirmed, pinned operation (see plan.md + research.md
  R13).
- **Cancellation**: all operations accept cancellation; a canceled operation
  leaves remote state consistent (no partial commit).
- **Retry classification**: adapters classify transient vs permanent failures
  via normalized errors (see provider-errors.md). The engine applies
  exponential backoff + jitter only to transient failures.
- **Credentials**: adapters receive credentials via Keychain-backed references,
  never via the protocol surface; credentials never appear in logs.

# Normalized Provider Errors

**Status**: Versioned | **Date**: 2026-08-06 | **Plan**: [../plan.md](../plan.md)

The normalized error vocabulary both WebDAV and S3-compatible adapters map to.
The synchronization engine branches on these, not on raw HTTP status text or S3
XML. Stable error domain: `sync.provider`. Sanitized codes only — no note
content, credentials, or full remote responses in user-facing messages or logs.

## Error categories

| Code | Meaning | Engine action |
|------|---------|---------------|
| `auth` | Authentication failed (bad credentials / token). | Non-blocking status; do NOT retry automatically; prompt re-entry. |
| `forbidden` | Authorized but not permitted for this object/path. | Non-blocking status; do not retry. |
| `conditionalFailed` | Conditional create/replace/delete precondition failed (object exists / version changed). | For manifest: re-fetch, re-compare, retry (bounded). For object create: acceptable (idempotent). |
| `notFound` | Object does not exist. | For fetch/manifest: treat as missing (download missing / reconcile). For delete: idempotent success. |
| `conflict` | Server-side conflict state (rare). | Re-fetch + retry (bounded). |
| `network` | Transient network failure (timeout, connection reset, DNS). | Exponential backoff + jitter; retry. |
| `server` | 5xx server error. | Exponential backoff + jitter; retry (bounded). |
| `clockSkew` | Request signature rejected due to clock skew (S3 SigV4). | Sync device clock; retry once; if persistent, surface a clear error. |
| `corrupt` | Retrieved object failed integrity (bad ciphertext/tag/hash). | Fail closed; do NOT accept the object; create a sanitized diagnostic; do not delete local data. |
| `schemaUnsupported` | Object envelope/manifest version unsupported. | Fail closed; surface "vault needs a newer app version"; do not mutate. |
| `canceled` | Operation canceled. | Stop; leave remote consistent. |
| `tls` | TLS/certificate failure (e.g. pinned cert mismatch). | Fail closed; require explicit re-confirmation (self-signed advanced flow). |
| `unknown` | Unrecognized provider response. | Sanitized diagnostic; do not retry indefinitely. |

## Rules

- Adapters MUST map every raw provider outcome into exactly one category.
- `corrupt`, `auth`, `forbidden`, `schemaUnsupported`, `tls`, and an unexpected
  context/decryption failure MUST **fail closed**: no local data is overwritten
  or deleted; no remote object is silently accepted.
- Logs record only the code + operation timing + object counts/sizes (no names,
  no content). User-facing messages are localized and reveal no sensitive
  technical detail.
- Transient categories (`network`, `server`, `conflict`, `clockSkew`) are
  eligible for bounded retry; permanent categories are not.

# Contract: sync-profile-export schema v2 (delta)

**Feature**: 002-join-existing-vault | **Date**: 2026-08-08 | **Plan**: [plan.md](./plan.md)

The authoritative JSON Schema lives at `specs/001-sticky-notes-app/contracts/
sync-profile-export.schema.json`. This feature bumps it from v1 → v2. This
document defines the exact delta that implementation (task T003) must apply;
the resulting file MUST validate all scenarios below.

## Change summary

| | v1 (current) | v2 (target) |
|---|---|---|
| `schemaVersion` | `const: 1` | `enum: [1, 2]` — both validate; v2 files carry schemaVersion 2 |
| `originDeviceName` | absent | **new**, optional, `type: string` (`maxLength: 100`), nullable-absent allowed |
| Required fields | schemaVersion, vaultId, vaultLocator, providerType, providerConfig, encryptionSuiteVersion | unchanged (same six) |
| `additionalProperties` | false | false (unchanged) |

Rules:

- `originDeviceName` is a user-readable display name of the exporting device
  (from the device identity, e.g. `AppDevice` displayName). It is NOT an
  identity field — the authoritative join identity remains `vaultLocator` /
  `vaultId`.
- Suggested bounds: `maxLength: 100`, no constraint on content (any
  user-visible device name).
- `providerConfig` stays REQUIRED and redacted: endpoint/prefix/region are
  connection info the receiving device needs to connect — NOT secrets
  (Constitution VI forbids credentials/keys/content). Credentials, keys, and
  note content are NEVER exported (FR-009/SC-004).
- v1 read-compatibility: a valid v1 file (schemaVersion 1, no
  originDeviceName) MUST validate against the v2 validator unchanged.
  Consumers treat absent originDeviceName as "unknown device".
- Version updates to the `description` MUST document v1 read-compat.

## Validation scenarios (implementation tests, T001/T013/T014)

1. **v1 file parses** under the v2 validator (backward compatible).
2. **v2 file round-trips**: export → validate → re-import preserves
   originDeviceName.
3. **Unsupported version fails**: schemaVersion 0 or 3 → validation failure
   (fail closed).
4. **Corrupt file fails**: non-JSON / missing required field → failure,
   no local config written.
5. **Export boundary**: exported JSON validates against the v2 schema AND
   contains no credentials, keys, or note content (content-boundary test).

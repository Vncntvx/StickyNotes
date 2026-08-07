# Security — macOS Sticky Notes (working title)

Applies Constitution Principle VII (E2E encryption by design) and VIII
(correct, non-destructive sync). This document is part of the M4
documentation set (T136).

## Threat model

The sync provider (WebDAV or S3-compatible host) is treated as
honest-but-curious: it must never learn note content, structure, file
names, or meaningful metadata (FR-160a). Accepted observable leakage
(FR-160b): opaque object IDs, sizes, modification times, network addresses,
access timing.

## Encryption stack

- **Password → KEK**: Argon2id (RFC 9106) with production minimums
  memory ≥ 19456 KiB, iterations ≥ 2, parallelism ≥ 1 (FR-160c). Schema
  minimums (8/1/1) exist only for deterministic test fixtures.
- **Master key**: random 32 bytes, wrapped by the KEK; never exposed.
- **Object keys**: HKDF-SHA-256 from the master key with context
  {vaultID, objectID, objectType, schemaVersion, encryptionSuiteVersion};
  the same context is the AES-GCM AAD.
- **Envelopes**: AES-GCM (CryptoKit). Fail closed (FR-160d) on each of the
  exhaustively enumerated inputs: wrong password, modified ciphertext,
  invalid/mismatched auth tag, mismatched object ID/type/vault,
  unsupported envelope version, corrupted/truncated structure. Each is a
  deterministic test vector.
- **Keychain**: credentials + remembered unlocked key material. No
  credentials in SQLite, UserDefaults, logs, or exported diagnostics.

## Wrong-password policy

Stateless and never rate-limited, throttled, or lockout-bounded (FR-160e):
the Argon2id KDF cost is the rate limiter. No cached password or derived key.

## Remember-unlock (FR-162a)

- `enabledUntilLockOrRestart`: the unwrapped key is stored in Keychain and
  restored silently at app launch ONLY when the boot timestamp matches
  (no restart) and the vault was not explicitly locked.
- Toggle-off while unlocked clears the Keychain item immediately but
  preserves the current unlocked session until explicit lock or exit.
- Not a login-item-bound daemon; restart/logout always requires the password.

## Wrong-vault detection

The bootstrap object's `vaultId` is authoritative. A configured or newly
chosen repository whose bootstrap `vaultId` differs fails closed with a
typed error; no local or remote data is modified.

## Sync safety

- Immutable remote objects; the manifest is the sync state; conditional
  commit with bounded retry.
- Divergence → conflict copies (deterministic dedup record), never
  overwrites. Sort-key-only divergence → per-note last-writer-wins
  (FR-022b). Deletions propagate via lineage-checked 30-day tombstones;
  long-offline devices reconcile remote deletion history before upload and
  never auto-delete local content (FR-174).
- HTTPS only; self-signed certs require explicit confirmation + pinning.
- No credentials in fixtures; credentialed tests opt in via CI secrets.

## Releases

Developer ID signing + notarization via `.github/workflows/release.yml`;
secrets in GitHub encrypted secrets only (T137).

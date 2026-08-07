# Architecture — macOS Sticky Notes (working title)

This document is part of the M4 documentation set (T136). The authoritative
design artifacts live in `specs/001-sticky-notes-app/` (spec, plan,
data-model, contracts); this file is a compact architecture overview for
contributors.

## Shape

A modular monolith, macOS 26+, Swift 6 language mode, strict concurrency:

```text
App (SwiftUI) + WidgetExtension
        │
        ├── SystemBridge   (AppKit/Carbon/ScreenCaptureKit/Security bookmarks)
        ├── EditorCore     (Markdown FSM, block ops, canonical conversion)
        ├── AssetStore     (atomic asset writes, thumbnails, hashing)
        ├── SecurityCore   (vault, Argon2id KDF, AES-GCM envelopes, Keychain)
        └── SyncCore       (provider protocol, WebDAV, S3-SigV4, sync engine)
                └── Domain ◄── Persistence (GRDB: WAL, FTS5, migrations)
```

Dependencies point downward only; Domain is Foundation-only. The App and
Widget targets depend on the package; the Widget links only Domain +
Persistence + GRDB (never SyncCore/SecurityCore).

## Local storage

- App Group container: SQLite (WAL, FTS5 external-content), asset bytes
  (originals/thumbnails/appIcons), first-launch prefs (UserDefaults).
- Keychain: sync credentials + remembered unlocked key material.
- One SQLite schema version per release; ordered named migrations
  (m0001…), pre-migration backup + interrupted-migration recovery.

## Sync

Optional, additive, E2E-encrypted (Argon2id KEK → random master key → HKDF
object keys → AES-GCM with contextual AAD). One vault, one provider
(WebDAV or S3-compatible). Objects are immutable; the manifest is the sync
state. Divergence → labeled conflict copies (deterministic dedup record);
sort-key-only divergence → per-note last-writer-wins (FR-022b); deletions
propagate via 30-day tombstones with lineage checks.

## Concurrency

- Main actor: UI models.
- `SyncActor` (single sync transaction per vault), `AssetStore` actor
  (serialized asset mutations).
- Repository protocols return `Sendable` snapshots; no concrete GRDB rows
  cross module boundaries.

## Editor

Seamless block model (6 categories) around a canonical rich-text document
(run/paragraph, scalar offsets, NFC). SwiftUI `TextEditor` + `AttributedString`
bridged through `RichTextAdapter`; only supported marks persist (FR-053).
Markdown is an input convenience with single-Undo; keystroke latency is
signpost-bracketed (SC-004a).

## Privacy & safety (Constitution)

- No analytics/telemetry, no developer backend; local-first, offline-complete.
- OSLog privacy annotations; sanitized error codes; exportable diagnostic
  bundle with a positively-enumerated field boundary (FR-191).
- Permissions on-demand only; screen-recording never requested at launch.
- Tests are mandatory and written first (Constitution XII).

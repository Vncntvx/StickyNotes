# Privacy — macOS Sticky Notes (working title)

Applies Constitution Principle VI (privacy & least privilege). This document
is part of the M4 documentation set (T136).

## Data model

- **Local-first**: all note data lives in the App Group container (SQLite +
  asset bytes). No developer-operated backend; no analytics; no telemetry;
  no account system.
- **Synchronized data** (when sync is configured) is end-to-end encrypted:
  the provider can only observe the accepted observable-leakage bound
  (opaque IDs, sizes, mod times, network addresses, access timing — FR-160b).
- **Never leaves the device**: security-scoped bookmark bytes, absolute
  paths, device-local window state, first-launch preferences,
  remember-unlock key material.

## Least privilege

- **Screen recording**: requested ONLY when the user invokes capture
  (`CGRequestWindowCaptureAccess` on capture invocation). Status checks use
  preflight APIs that never prompt.
- **Accessibility**: reserved for future advanced window-identification;
  never requested at startup or during ordinary capture.
- **File references**: security-scoped bookmarks grant access to exactly the
  user-selected file. No filesystem-wide scan.

## Logs & diagnostics

- OSLog dynamic values are private by default; error codes are sanitized
  (no note content, titles, paths, credentials, key material).
- The exportable diagnostic bundle (FR-191) contains ONLY the positively
  enumerated fields: app version, macOS version, schema version, provider
  type (never endpoint/hostname), normalized error categories + timestamps
  (last 30 days), sync run counts/durations, aggregate object counts, vault
  state, permission statuses. Any field not in the list is excluded by
  default.

## Widgets

- Widget-eligible notes only (per-note privacy gate, FR-112). Widget
  snapshots/placeholders carry no content; the "temporarily unavailable"
  placeholder never implies an excluded note exists.

## Data deletion

- Trash (30-day recoverability) → permanent deletion retains a tombstone
  for sync-safety. Empty Trash is an explicit, confirmed batch action.
- Removing the sync configuration never deletes local notes; replacing a
  repository never auto-deletes the prior repository's remote data.

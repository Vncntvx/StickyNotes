<!--
Sync Impact Report
==================
Version change: 1.0.0 → 2.0.0

Modified principles:
  VI (Privacy and Least Privilege) — amended 2026-08-08: the accessibility
  permission clause now permits an EXPLICIT, user-initiated request from the
  Settings permissions page (an informed user action), while keeping the
  prohibitions on startup/first-launch/ordinary-use requests and on requests
  made merely because a future feature might use the permission. This is a
  MAJOR version change because it redefines a non-negotiable privacy
  guarantee (when the accessibility permission may be requested).

Added sections:
  None.

Removed sections:
  None.

Files changed by this operation:
  - .specify/memory/constitution.md (this file)

Files reviewed but NOT modified (dependent templates/commands read the
constitution at runtime; see Scope Guard):
  - .specify/templates/plan-template.md
  - .specify/templates/spec-template.md
  - .specify/templates/tasks-template.md
  - .claude/skills/speckit-plan/SKILL.md, speckit-specify/SKILL.md,
    speckit-tasks/SKILL.md (and related command/agent guidance)

Files requiring manual follow-up (intentionally deferred — outside the
constitution operation per Scope Guard):
  1. .specify/templates/spec-template.md — Constitution Principle XIV
     requires every feature spec to define: user problem/outcome, in/out
     scope, observable acceptance criteria, data/migration implications,
     privacy/permission implications, accessibility implications,
     performance expectations, failure/recovery behavior, synchronization
     implications (when applicable), and required tests. The current
     spec-template.md provides User Scenarios, Requirements, and Success
     Criteria but LACKS mandatory sections for: scope (in/out), data &
     migration implications, privacy & permission implications,
     accessibility implications, performance expectations, failure &
     recovery behavior, and synchronization implications. ACTION: when
     next editing the spec template (or via a template-update task),
     add these mandatory subsections so generated specs are
     constitution-compliant by construction.
  2. .specify/templates/plan-template.md — its Constitution Check section
     reads "[Gates determined based on constitution file]", which is
     correct (runtime). No change required, but plans generated from it
     MUST map decisions to the fourteen principles. No template edit
     needed; enforcement happens at plan-generation time.
  3. .specify/templates/tasks-template.md — its "Tests" note currently
     states tests are OPTIONAL. Principle XII (Verification and Testing
     Are Mandatory) and Principle XIV make tests MANDATORY for feature
     completion. The tasks-template comment should be reconciled so task
     lists treat tests, migrations, accessibility, privacy, error
     handling, documentation, performance validation, and synchronization
     compatibility as required work (not optional). ACTION: update the
     tasks-template wording in a follow-up so it does not contradict
     Principle XII/XIV.
  4. Repository documentation — no README or docs exist yet, so there are
     no conflicts to resolve at this time. Future top-level docs (README,
     PRIVACY, SECURITY) MUST be kept consistent with Principles VI and VII.

Intentionally deferred updates: none within the constitution itself. All
bracketed template tokens have been resolved. No TODO placeholders remain.
-->

# StickyNotes Constitution

This constitution is the highest-level engineering and product authority
for the StickyNotes repository. All specifications, plans, tasks,
implementation decisions, reviews, migrations, and releases MUST be
evaluated against it. It uses normative language consistently: **MUST**
and **MUST NOT** denote non-negotiable requirements; **SHOULD** and
**SHOULD NOT** denote strong defaults that require documented
justification to violate; **MAY** denotes explicitly optional behavior.

## Core Principles

### I. Focused Sticky-Notes Product

The application MUST remain a focused sticky-notes utility rather than
evolve into a general-purpose knowledge-management platform.

The core product responsibilities are:

- Rapidly capture information.
- Keep information visible when needed.
- Retrieve notes quickly.
- Support lightweight formatting and todo items.
- Associate static screenshots and file references with notes.
- Optionally synchronize encrypted notes between Macs.

The project MUST NOT introduce any of the following unless this
constitution is formally amended:

- User accounts managed by the project.
- Developer-operated cloud storage.
- Advertising.
- Analytics, tracking, behavioral telemetry, or user-content collection.
- Multi-user collaboration.
- Real-time shared editing.
- Drawing or handwriting tools.
- Calendars, reminders, alarms, or project-management workflows.
- Databases, relation graphs, backlinks, or Notion-style knowledge
  systems.
- Live monitoring or continuous recording of application windows.
- Plugins that can execute untrusted code.

New features MUST directly improve the capture, editing, visibility,
retrieval, portability, privacy, reliability, or accessibility of sticky
notes. Feature count is not a measure of success; simplicity and
coherence take priority over expanding scope.

### II. Native macOS and SwiftUI-First

The minimum supported operating system MUST be macOS 26.

User-facing interfaces MUST be implemented with SwiftUI unless a
documented platform limitation makes a SwiftUI implementation impossible,
unreliable, inaccessible, or materially inferior.

AppKit MAY be used only through small, isolated system-adapter modules
for capabilities such as:

- Precise `NSWindow` behavior.
- Per-window floating levels.
- Window positioning and display restoration.
- Dock activation-policy switching.
- Global keyboard shortcuts.
- Security-scoped file access integration.
- Advanced accessibility-based window identification.
- Platform behavior not reliably exposed by SwiftUI.

AppKit types MUST NOT leak throughout feature and domain layers. The
project MUST NOT adopt a cross-platform UI framework.

The application MUST follow macOS conventions for windows, menus,
keyboard commands, drag and drop, accessibility, focus, appearance, and
permissions. Platform-native solutions MUST be preferred over custom
imitations when Apple provides an appropriate system interface.

### III. Local-First and Offline-Complete

The local application database MUST be the source of truth.

All note creation, editing, searching, deletion, restoration,
file-reference handling, screenshot viewing, and window management MUST
work without:

- An Internet connection.
- A user account.
- A configured synchronization provider.
- Access to any developer-operated service.

Network synchronization MUST be optional. Local writes MUST complete
independently of network availability, and editing MUST NOT wait for
remote requests. Synchronization failures MUST NOT prevent users from
viewing or editing local data.

The application MUST save user changes automatically and MUST NOT
require a manual Save command for normal note editing. A remote
synchronization repository is an encrypted replication and exchange
mechanism, not the primary application database.

### IV. Explicit, Durable, and Versioned Data

The primary local database MUST use SQLite through GRDB unless this
constitution is amended. All persistent entities MUST use stable UUID
identifiers.

Database changes MUST use explicit, ordered, tested migrations.
Destructive schema replacement is prohibited unless accompanied by an
explicit export, migration, and recovery strategy.

The application MUST define its own versioned, canonical data
representation for:

- Notes.
- Blocks.
- Rich-text attributes.
- Todo items.
- Assets.
- Tombstones.
- Synchronization metadata.

Platform-private object archives MUST NOT be used as the canonical
synchronization or export format. The canonical synchronization
representation SHOULD use deterministic, versioned JSON for structured
data and independently stored binary objects for assets.

Rich text MUST store only formatting capabilities explicitly supported
by the application. Unsupported or private attributed-string properties
MUST NOT silently enter the durable format.

Every format change MUST define:

- A schema version.
- Backward-compatibility behavior.
- Migration behavior.
- Failure behavior.
- Tests using previous-version fixtures.

Asset writes MUST be atomic. Asset records SHOULD include hashes to
detect corruption and avoid accidental duplication.

### V. Structured Editor Integrity

The editor MUST use a seamless block model while preserving the visual
simplicity of a normal sticky note. Supported block categories are:

- Rich-text block.
- Todo block.
- Code block.
- File-reference block.
- Embedded-image block.
- Screenshot block.

Normal prose MUST remain comfortable to edit as continuous rich text.
The product MUST NOT resemble a complex page-builder interface.

Every todo item MUST have a stable UUID independent of its text. This
identity MUST be used by the main application, widgets, the
synchronization engine, and conflict handling.

Markdown-style input is an input convenience, not the canonical storage
format. Markdown conversion MUST obey these rules:

- Line-level syntax converts at the appropriate space or line transition.
- Inline syntax converts after a valid closing delimiter.
- Conversion is finalized when the insertion point leaves the range or
  the user confirms the line.
- One Undo action MUST restore the original Markdown syntax and
  formatting state.
- Markdown conversion MUST behave correctly with marked text and
  input-method composition.

Code blocks MUST initially support:

- Monospaced rendering.
- Preserved whitespace.
- A copy button.
- An optional language label.
- Optional wrapping or horizontal scrolling.

Syntax highlighting and code execution are outside the initial scope.

A note title MUST be optional. When no manual title exists, the UI MAY
display the first meaningful content as a temporary summary, but MUST
NOT silently write that summary into the title field.

### VI. Privacy and Least Privilege

The application MUST collect no analytics, tracking data, behavioral
telemetry, or note content.

Logs MUST NOT contain:

- Note titles.
- Note bodies.
- Todo text.
- Code contents.
- File names or file paths.
- Window titles.
- Screenshot text.
- Credentials.
- Encryption keys.
- Synchronization passwords.
- Access tokens.
- Unredacted server responses containing user data.

Permissions MUST be requested only when the user invokes a feature that
requires them. Screen-recording permission MUST be requested only when the
user first attempts screenshot capture or window capture. Accessibility
permission MUST be reserved for explicit advanced window-identification
functionality; the application MUST NOT request it during startup, on first
launch, or during ordinary note editing, and MUST NOT request it merely
because the application might need it in the future. The application MAY
request accessibility permission when the user explicitly and knowingly
chooses to grant it from the Settings permissions page — a user-initiated
action that invokes the system accessibility prompt, never an automatic or
startup-time request (amended 2026-08-08, Constitution 2.0.0).

Declining a permission MUST degrade only the affected feature; ordinary
notes MUST remain fully usable.

Widget privacy MUST be controlled per note. Notes prohibited from
widgets MUST NOT expose their title, content, todo items, screenshot, or
summary through widget timelines, previews, placeholders, or logs.

The project MUST maintain a clear privacy document describing local
storage, permissions, synchronization, encryption, and diagnostic data.

### VII. End-to-End Encryption by Design

All synchronized user content and meaningful metadata MUST be encrypted
before leaving the device.

The remote provider MUST NOT be able to read:

- Note titles.
- Note contents.
- Todo text.
- Code blocks.
- File-reference names.
- Application names.
- Window titles.
- Screenshot captions.
- Device display names.
- Object types.

Remote object names MUST be random or otherwise opaque.

The encryption design MUST use established cryptographic primitives:

- Argon2id for deriving a key-encryption key from the synchronization
  password.
- A random master key for vault data.
- HKDF for deriving context-specific object keys.
- AES-GCM for authenticated object encryption.
- macOS Keychain for locally stored secrets and credentials.

The project MUST NOT implement its own cryptographic algorithms.

The user password MUST protect the random master key rather than
directly encrypt every object. Changing the password SHOULD require
re-wrapping the master key rather than re-encrypting all synchronized
data.

Each encrypted object MUST use authenticated contextual metadata so that
ciphertext cannot be substituted across object identifiers, object types,
vaults, or schema versions. Incorrect passwords, modified ciphertext,
invalid authentication tags, and unexpected object contexts MUST fail
closed.

The application MUST clearly tell users that forgotten synchronization
passwords make remote encrypted data unrecoverable. The project MUST NOT
claim to offer password recovery when it cannot decrypt the data.

Cryptographic formats MUST be documented and covered by deterministic
test vectors.

### VIII. Correct and Non-Destructive Synchronization

The first supported synchronization topology MUST allow exactly one
configured repository at a time: one WebDAV repository, or one
S3-compatible repository. S3 support MUST allow a configurable endpoint
and MUST NOT assume AWS-hosted S3 exclusively.

Synchronization MUST operate on independently encrypted objects rather
than uploading the complete local database as one object. Synchronization
operations MUST be:

- Idempotent.
- Retry-safe.
- Cancelable where practical.
- Resistant to partial upload and partial download.
- Explicit about version and precondition failures.
- Non-blocking to local editing.

A synchronization conflict MUST NOT silently overwrite either valid
version. When divergent versions of the same note are detected, the
system MUST preserve both by creating a clearly labeled conflict copy.
The initial implementation MUST NOT attempt unsafe character-level or
block-level automatic merging.

Deletion MUST use tombstones so an offline device cannot silently
resurrect a deleted note. Deleted notes and remote tombstones MUST be
retained for 30 days before automatic cleanup, subject to
synchronization-safety checks.

WebDAV and S3 credentials MUST be stored in Keychain. Only HTTPS
connections are permitted. Trusting a self-signed certificate MUST
require an explicit advanced user action and a clear security warning.

Remote errors MUST be visible through non-blocking status and
diagnostics without interrupting normal local editing.

### IX. File References Are Not Cloud Attachments

Files dragged from Finder MUST be represented as references, not
automatically copied into the application or uploaded to synchronization
storage.

Long-term local access MUST use security-scoped bookmarks.
Security-scoped bookmark data and absolute local paths MUST remain
device-local and MUST NOT be synchronized.

The synchronized portion of a file-reference block MAY contain safe
generic metadata such as:

- Stable block ID.
- Display name.
- Content type.
- Approximate file size.
- Origin device ID.
- Added date.

The actual file content MUST NOT be synchronized unless a future
constitutional amendment explicitly introduces an opt-in attachment
system.

Ordinary drag-out behavior MUST copy the referenced file and MUST NOT
silently move or delete the original. Moving the source file MUST require
an explicit command, destination selection, and confirmation.

When a file cannot be located, the application MUST preserve the
reference card and offer relinking. It MUST NOT automatically search the
entire filesystem or silently delete the card.

### X. Consistent, Accessible, and Reversible UX

The application MUST preserve the following product behaviors:

- The menu bar is the primary entry point.
- The menu bar library uses a note-card grid.
- Clicking outside the menu bar window dismisses it.
- Clicking a note opens or focuses one independent window for that note.
- The same note MUST NOT accidentally open duplicate windows.
- Closing a note window hides it and does not delete it.
- Note windows are not automatically restored after application relaunch.
- Each note can independently enable Always on Top.
- The first release does not display notes across every Space.
- The Dock icon is enabled by default and can be disabled.
- Settings, Help, About, and Quit remain reachable from the menu-bar
  interface when the Dock icon is disabled.
- Off-screen windows are moved back into a visible display area without
  discarding the preferred frame for a disconnected display.

Destructive actions MUST be explicit and reversible where practical.
Deleted notes MUST enter a 30-day Trash before automatic cleanup.

The application MUST support keyboard-first operation. All interactive
controls MUST have meaningful accessibility labels and states. Color MUST
NOT be the only way to communicate status.

Text and controls MUST maintain readable contrast across:

- Light mode.
- Dark mode.
- Custom note colors.
- Supported transparency levels.
- Increased-contrast settings.

The application MUST support VoiceOver, Reduce Motion, keyboard
navigation, Chinese and English text, font fallback, emoji, and
input-method composition.

Widgets MUST support lightweight viewing and actions, but MUST NOT
attempt full rich-text editing.

### XI. Performance and Responsiveness Are Product Requirements

User-visible interfaces MUST remain responsive during:

- Database access.
- Search.
- Encryption.
- Synchronization.
- Image decoding.
- Thumbnail generation.
- File access.
- Screenshot processing.

Network access, cryptographic operations, image processing, and large
file operations MUST NOT execute synchronously on the main actor.

The architecture MUST use structured Swift concurrency and explicit
actor isolation for mutable shared services. The synchronization engine
MUST serialize mutations for one vault so that overlapping
synchronization runs cannot corrupt state.

Images and thumbnails MUST be loaded lazily. The application MUST NOT
decode every full-resolution screenshot while displaying the note
library.

The project SHOULD meet these initial performance targets on supported
hardware:

- Warm menu-bar window presentation within 150 milliseconds.
- Initial card content visible within 300 milliseconds.
- New note window presentation within 200 milliseconds.
- Search across 10,000 primarily textual notes within 200 milliseconds.
- No sustained CPU use while idle.
- No high-frequency polling while synchronization is inactive.

Performance-sensitive behavior MUST be measured. Optimizations MUST NOT
compromise correctness, privacy, or maintainability.

### XII. Verification and Testing Are Mandatory

Tests are part of the implementation, not optional follow-up work. Every
feature plan MUST identify its required tests before implementation tasks
are considered complete.

At minimum, the project MUST maintain:

- Unit tests for domain and transformation logic.
- Database migration tests.
- Rich-text serialization tests.
- Markdown conversion and Undo tests.
- Todo identity, hierarchy, and ordering tests.
- Window-frame correction tests.
- File-reference and bookmark-state tests.
- Encryption test vectors.
- Authentication-failure tests.
- Synchronization conflict tests.
- Tombstone lifecycle tests.
- WebDAV integration tests.
- S3-compatible integration tests.
- Main-app and widget database-concurrency tests.
- UI tests for critical menu-bar and note-window flows.
- Regression tests for fixed defects.

Editor tests MUST include:

- Simplified Chinese input.
- Marked-text composition.
- English input.
- Mixed Chinese and English.
- Emoji.
- Pasted rich text.
- Undo and Redo across automatic formatting transformations.

Synchronization tests MUST inject failures such as:

- Offline transitions.
- Interrupted upload.
- Interrupted download.
- Authentication failure.
- Conditional-write failure.
- Missing objects.
- Corrupt ciphertext.
- Concurrent edits.
- Delete-versus-edit conflicts.
- Devices returning after extended offline periods.

A feature MUST NOT be considered complete when its required automated
tests are missing or failing. Test fixtures MUST contain no production
credentials, personal content, or recoverable secrets.

### XIII. Dependency Discipline and Maintainability

The project MUST minimize third-party dependencies. The initially
approved dependencies are:

- GRDB for SQLite access.
- One small, maintained, auditable Argon2id implementation.

WebDAV, S3 Signature Version 4, synchronization orchestration,
encryption-envelope logic, and networking SHOULD be implemented using
Apple frameworks and project-owned code rather than large vendor SDKs.

Any additional dependency MUST include a documented decision covering:

- Why Apple frameworks or a small internal implementation are
  insufficient.
- Maintenance activity.
- Security history.
- License compatibility.
- Binary and build-size impact.
- Transitive dependencies.
- Replacement strategy.
- Removal strategy.

Third-party UI frameworks, broad state-management frameworks,
dependency-injection frameworks, analytics SDKs, and complete
cloud-provider SDKs are prohibited by default.

Modules MUST have explicit responsibilities and narrow interfaces.
System adapters, domain logic, persistence, synchronization,
cryptography, and UI MUST remain separable and testable. Shared core
code MUST NOT depend on concrete views. Publicly documented formats and
protocols MUST be treated as compatibility contracts.

### XIV. Spec-Driven Traceability

Specifications are the source of behavioral intent. No significant
feature should proceed directly from an informal idea to implementation.

Every feature specification MUST define:

- User problem and intended outcome.
- In-scope and out-of-scope behavior.
- Observable acceptance criteria.
- Data and migration implications.
- Privacy and permission implications.
- Accessibility implications.
- Performance expectations.
- Failure and recovery behavior.
- Synchronization implications when applicable.
- Required tests.

Every implementation plan MUST include a Constitution Check mapping
relevant decisions to these principles. Every task list MUST include work
required for:

- Tests.
- Migrations.
- Accessibility.
- Privacy.
- Error handling.
- Documentation.
- Performance validation.
- Synchronization compatibility where applicable.

Implementation changes that alter behavior, data formats, security
properties, or user-visible contracts MUST update the corresponding
specification and tests in the same change. Unresolved contradictions
between a feature request and this constitution MUST be resolved before
implementation begins.

## Governance

### Constitutional Authority

This constitution supersedes local coding preferences, temporary
implementation convenience, individual feature documents, and
undocumented assumptions. Feature specifications and plans may add
stricter constraints but may not weaken this constitution.

### Amendment Process

An amendment MUST include:

1. The exact proposed textual change.
2. The reason for the change.
3. Product and engineering impact.
4. Security and privacy impact.
5. Compatibility and migration impact.
6. Required documentation and test changes.
7. A constitution version change.
8. Explicit approval before affected implementation begins.

Temporary exceptions MUST be documented in an architecture decision
record. An exception record MUST include:

- The violated principle.
- Why compliance is currently impractical.
- The narrow permitted scope.
- Risk mitigation.
- The responsible owner.
- An expiration date or removal condition.

Exceptions MUST NOT be used to bypass encryption, privacy, data
integrity, or non-destructive conflict requirements.

### Constitution Versioning

This constitution uses semantic versioning:

- **MAJOR**: Removes a principle, reverses a principle, or changes a
  non-negotiable product, privacy, security, or data-integrity guarantee.
- **MINOR**: Adds a principle or materially expands mandatory guidance.
- **PATCH**: Clarifies wording without changing the intended
  requirements.

Every amendment MUST update the version and last-amended date.

### Compliance Review

A Constitution Check MUST be performed during:

- Feature specification.
- Clarification.
- Technical planning.
- Task generation.
- Pre-implementation analysis.
- Code review.
- Release preparation.

Reviewers MUST reject changes that violate the constitution without an
approved amendment or time-limited exception.

**Version**: 2.0.0 | **Ratified**: 2026-08-06 | **Last Amended**: 2026-08-08

# Requirements Quality Checklist: Encryption, Privacy & Sync Safety

**Purpose**: Validate the *quality of the written requirements* (not the
implementation) for the encryption, privacy, and synchronization-safety domain
of the macOS Sticky Notes spec — the highest-risk, non-negotiable area governed
by constitutional principles VII (E2E encryption), VIII (non-destructive sync),
IX (file references not attachments), and VI (privacy & least privilege). This
is a "unit test suite for the English": each item asks whether a requirement is
complete, clear, consistent, measurable, and traceable.
**Created**: 2026-08-06
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) · [data-model.md](../data-model.md) · [contracts/](../contracts/)
**Domain**: Encryption / Privacy / Synchronization safety
**Depth**: Standard (PR review gate)
**Traceability**: Strong — every item cites a FR/SC/contract/constitution anchor

## Requirement Completeness

- [X] CHK001 - Are requirements specified for encrypting *every* synchronized object type listed in FR-161 (titles, bodies, todos, code, file-ref names, app names, window titles, captions, device display names, object types), with none left implicit? [Completeness, Spec §FR-161]
- [X] CHK002 - Is "meaningful metadata" in FR-160 explicitly enumerated so reviewers can decide whether a newly added field is in or out of scope for encryption? [Completeness, Gap, Spec §FR-160]
- [X] CHK003 - Are requirements defined for the full vault lifecycle: bootstrap, unlock, optional remember-unlock, lock, local-remembered-state removal, Keychain failure, password-changed-elsewhere, and wrong-vault-selected? [Completeness, Gap, Plan §Encryption architecture / Key lifecycle]
- [X] CHK004 - Are requirements specified for object-key derivation context fields (vaultID, objectID, objectType, schemaVersion, encryptionSuiteVersion) being used as authenticated associated data? [Completeness, Contracts §encrypted-envelope.schema.json]
- [X] CHK005 - Are requirements defined for what happens to *assets* (originals, thumbnails, app icons) during synchronization — independent encrypted objects, integrity hashes, partial-failure retry — beyond note objects? [Completeness, Gap, Spec §FR-090 / data-model §Asset]
- [X] CHK006 - Are requirements specified for the remote manifest's conditional-write (If-Match) behavior and the bounded retry-on-precondition-failure? [Completeness, Spec §FR-170 / Contracts §encrypted-manifest.schema.json]
- [X] CHK007 - Are requirements defined for tombstone retention behavior across each defined case: offline <30 d, offline >30 d, delete-vs-edit, deleted asset refs, device returning after remote cleanup, unknown devices, manual Trash emptying? [Completeness, Spec §FR-174 / data-model §Tombstone lifecycle]
- [X] CHK008 - Are requirements specified for repository-replacement and password-change workflows (enable sync, join vault, wrong password, another-vault repo, disable-sync-retain-local, replace WebDAV↔S3, change password, recover from partial propagation)? [Completeness, Gap, Plan §Repository replacement]
- [X] CHK009 - Are requirements defined for the exportable diagnostic bundle's *content boundaries* (what is included) matching FR-191's exclusions (what is omitted)? [Completeness, Spec §FR-191 / Plan §Diagnostics]
- [X] CHK010 - Are requirements specified for self-signed certificate trust as an advanced option (explicit confirmation, pinning, change detection, secure storage, warning) — not merely "HTTPS only"? [Completeness, Spec §FR-150 / Plan §WebDAV adapter]

## Requirement Clarity

- [X] CHK011 - Is "the remote service may inevitably observe random object identifiers, object sizes, modification times, network addresses, and access timing" (an accepted leakage bound) explicitly stated as a *non-violation* so reviewers do not treat it as a privacy gap? [Clarity, Spec §End-to-end synchronization privacy / Assumptions]
- [X] CHK012 - Is "fail closed" quantified or enumerated with the exact inputs that must trigger it (wrong password, modified ciphertext, invalid tag, mismatched object ID/type/vault, unsupported envelope version)? [Clarity, Spec §FR-160 / Contracts §provider-errors.md]
- [X] CHK013 - Is "meaningful metadata" vs "inevitably observable metadata" distinguished clearly enough that a future contributor cannot accidentally upload an unencrypted field in the former category? [Clarity, Gap, Spec §FR-160]
- [X] CHK014 - Is the password-change requirement (FR-164 "SHOULD NOT require unnecessarily uploading all unchanged content again") clarified to require re-wrapping the master key rather than re-encrypting objects? [Clarity, Spec §FR-164 / Contracts §vault-bootstrap.schema.json]
- [X] CHK015 - Is the 30-day tombstone retention (FR-174) clarified as *sync-safety-gated* (not a hard wall-clock purge that could resurrect a note)? [Clarity, Spec §FR-174 / data-model §Tombstone lifecycle]
- [X] CHK016 - Is "one repository at a time" (FR-154) clarified to define what happens if the user attempts to configure a second (replace vs reject)? [Clarity, Gap, Spec §FR-154]
- [X] CHK017 - Are credential-storage requirements (Keychain) explicit about *which* items go where (WebDAV password/token, S3 access/secret keys, session token, remembered unlocked key, cert trust records) versus "in Keychain" generically? [Clarity, Spec §FR-151 / Plan §Local storage]
- [X] CHK018 - Is "credentials and unlocked secrets MUST NEVER appear in logs or ordinary exported diagnostics" (FR-165) clarified to include intermediate forms (derived keys, nonces used as identifiers, redacted config)? [Clarity, Gap, Spec §FR-165]

## Requirement Consistency

- [X] CHK019 - Do FR-160/FR-161 (encryption before upload) align with the contracts (envelope AAD context, opaque remote names, no semantic type in filenames)? [Consistency, Spec §FR-160 / Contracts §encrypted-envelope.schema.json]
- [X] CHK020 - Does FR-164 (password change re-wrap only) align with vault-bootstrap.schema.json (wrappedMasterKey) and the data-model VaultConfiguration (rememberedUnlock)? [Consistency, Spec §FR-164 / Contracts §vault-bootstrap.schema.json / data-model §VaultConfiguration]
- [X] CHK021 - Does the "delete-vs-edit → recovered conflict copy" requirement (FR-173) align with the conflict-copy lifecycle and tombstone lifecycle in data-model (no silent loss, no resurrection)? [Consistency, Spec §FR-173 / data-model §Conflict-copy lifecycle / Tombstone lifecycle]
- [X] CHK022 - Does FR-174 (30-day tombstone) align across spec, plan (tombstone retention + sync-safety), and contracts (encrypted-manifest tombstones + tombstone.schema.json deletedAt)? [Consistency, Spec §FR-174 / Contracts §tombstone.schema.json]
- [X] CHK023 - Do the privacy-exclusion lists in FR-161 (remote cannot read) and FR-191 (logs/diagnostics cannot contain) use a consistent item set, or do they diverge in a way that implies a gap? [Consistency, Spec §FR-161 vs §FR-191]
- [X] CHK024 - Does FR-009's widget deep-link rule (must not flip Dock policy) align with the deep-links contract (window uniqueness, no sync init) and FR-008 (Dock default-on, disable-able)? [Consistency, Spec §FR-008/FR-009 / Contracts §deep-links.md]
- [X] CHK025 - Does the file-reference requirement (only generic metadata syncs, FR-104/FR-105) align with data-model FileReference (no bookmark) vs FileLocator (device-local) and the block-payloads contract (fileRef payload has no path/bookmark)? [Consistency, Spec §FR-104 / data-model §FileReference / Contracts §block-payloads.schema.json]
- [X] CHK026 - Does FR-153 (local editing must not wait for sync) align with FR-142 (network failures never block local editing) and SC-007 (offline work continues)? [Consistency, Spec §FR-142/FR-153/SC-007]

## Acceptance Criteria & Measurability

- [X] CHK027 - Is SC-010 ("no exported diagnostic or log contains note content, file names/paths, window titles, credentials, passwords, or encryption secrets") stated as a machine-checkable boundary, or only as prose? [Measurability, Spec §SC-010]
- [X] CHK028 - Are the encryption correctness requirements measurable via deterministic test vectors (correct/wrong password, modified ciphertext/nonce/AAD, wrong object ID/type/vault, unsupported version) as enumerated in plan's security tests? [Measurability, Plan §Security tests / Contracts §provider-errors.md]
- [X] CHK029 - Is "fail closed" verifiable as an objective outcome (no local data overwritten, no remote object silently accepted) rather than a subjective judgment? [Measurability, Spec §FR-160 / Contracts §provider-errors.md]
- [X] CHK030 - Can the 30-day tombstone / conflict-copy / remote-deletion requirements be objectively verified via the sync failure-injection scenarios (offline, interrupted upload/download, delete-vs-edit, long-offline device)? [Measurability, Spec §FR-173/FR-174 / Plan §Synchronization tests]
- [X] CHK031 - Is the "no sustained CPU while idle / no high-frequency polling while sync inactive" requirement (SC-006) measurable without dictating implementation? [Measurability, Spec §SC-006]
- [X] CHK032 - Can "changing the password should not require unnecessarily uploading all unchanged content again" (FR-164) be verified as a bounded operation (re-wrap only) without ambiguity over "unnecessarily"? [Measurability, Spec §FR-164]

## Scenario Coverage (Encryption/Privacy/Sync)

- [X] CHK033 - Are Primary scenario requirements complete for initial vault onboarding + first upload + first download on a second Mac? [Coverage, Spec §US9 / Plan §Synchronization tests]
- [X] CHK034 - Are Alternate scenario requirements defined for switching providers (WebDAV↔S3) while retaining local notes and without deleting remote data? [Coverage, Gap, Plan §Repository replacement]
- [X] CHK035 - Are Exception/Error scenario requirements defined for each normalized provider error category (auth, conditionalFailed, corrupt, schemaUnsupported, tls, clockSkew, network, server, canceled)? [Coverage, Contracts §provider-errors.md]
- [X] CHK036 - Are Recovery scenario requirements defined for: interrupted manifest commit, interrupted upload/download, partial asset sync failure, and a device returning after remote object cleanup? [Coverage, Gap, Plan §Synchronization tests / data-model §Asset syncFailureState]
- [X] CHK037 - Are Non-Functional scenario requirements defined for synchronization under network loss + restoration, and for bounded termination (sync must not block app quit indefinitely)? [Coverage, Spec §FR-152 / Plan §Sync engine]
- [X] CHK038 - Are requirements defined for the conflict-copy deduplication case so retrying the same reconciliation does not create unbounded duplicates? [Coverage, Plan §Conflict model / data-model §Conflict-copy lifecycle]
- [X] CHK039 - Are requirements defined for widget privacy when a note is widget-ineligible (no title/body/todo/screenshot/summary in timelines/previews/placeholders/snapshots/logs)? [Coverage, Spec §FR-112 / Contracts §deep-links.md]
- [X] CHK040 - Are requirements defined for permission denial graceful degradation (screen-recording denied → notes usable + screenshot explanation + open settings; accessibility denied → only advanced window-id unavailable)? [Coverage, Spec §FR-132/FR-133]

## Edge Case Coverage

- [X] CHK041 - Is the delete-vs-edit edge case (one device deletes while an offline device modifies) specified to preserve the modified content as a recovered conflict copy — neither lost nor resurrecting the original? [Edge Case, Spec §FR-173]
- [X] CHK042 - Is the "device offline >30 days, tombstone already purged remotely" edge case specified so the returning device does not auto-delete local content and reconciles conservatively? [Edge Case, data-model §Tombstone lifecycle / research.md R15]
- [X] CHK043 - Is the "wrong vault selected" / "repo contains another vault" edge case specified to fail safely without corrupting either vault? [Edge Case, Gap, Plan §Repository replacement]
- [X] CHK044 - Is the "corrupt ciphertext / invalid tag / unexpected object context" edge case specified to fail closed without deleting local data or accepting the remote object? [Edge Case, Spec §FR-160 / Contracts §provider-errors.md]
- [X] CHK045 - Is the "file-reference original moved or missing" edge case specified to preserve the card + offer relink, never auto-scan the filesystem or silently delete the card? [Edge Case, Spec §FR-103]
- [X] CHK046 - Is the "multi-card referencing the same file after an explicit move" edge case specified (only the initiating card's bookmark updates; others report missing + relink)? [Edge Case, research.md R8]
- [X] CHK047 - Is the "todo toggled from a widget while the note is open and being edited on another Mac" edge case specified to preserve stable todo identity and reconcile without loss? [Edge Case, Spec §FR-071 / data-model §TodoItem]
- [X] CHK048 - Is the "self-signed certificate changes after pinning" edge case specified to reject with a clear warning and require re-confirmation? [Edge Case, Plan §WebDAV adapter / research.md R13]
- [X] CHK049 - Is the "Keychain unavailable / corrupt bootstrap" edge case specified for both local secret retrieval and vault opening? [Edge Case, Plan §Security tests]
- [X] CHK050 - Is the "S3-compatible ETag/conditional-write variance across providers" edge case specified so the manifest-as-serialization-point design holds (AWS S3, R2, MinIO, B2)? [Edge Case, Plan §S3-compatible adapter / research.md R11]

## Non-Functional Requirements (Security/Privacy/Performance)

- [X] CHK051 - Are cryptographic primitive requirements pinned to established ones (Argon2id KEK, random master key, HKDF-SHA-256, AES-GCM, Keychain) with an explicit prohibition on hand-rolled crypto? [Non-Functional, Constitution §VII / Plan §Encryption architecture]
- [X] CHK052 - Is the dependency-discipline requirement (only GRDB + one audited Argon2id; no AWS SDK; project-owned WebDAV/SigV4/crypto-envelope) specified with a documented add-dependency decision process? [Non-Functional, Constitution §XIII / Plan §Dependencies]
- [X] CHK053 - Are performance requirements specified for the encryption/sync hot paths off the Main Actor (password derivation, large-asset encryption, manifest comparison) without dictating implementation? [Non-Functional, Constitution §XI / Plan §Concurrency]
- [X] CHK054 - Is the "no analytics / no telemetry / no behavioral tracking / no content collection / no developer backend" requirement (FR-190) specified as a product-level invariant, not just an implementation choice? [Non-Functional, Spec §FR-190 / Constitution §VI]
- [X] CHK055 - Is the synchronization-engine serialization requirement (one transaction per vault at a time) specified so overlapping runs cannot corrupt state? [Non-Functional, Constitution §XI / Plan §Sync engine]
- [X] CHK056 - Are HTTPS-only + Keychain-credential requirements specified as non-negotiable transport/storage guarantees? [Non-Functional, Spec §FR-150 / Constitution §VIII]

## Dependencies & Assumptions

- [X] CHK057 - Is the assumption "user supplies their own WebDAV/S3 repository; project provides no hosted service" documented and reflected in the sync requirements? [Assumption, Spec §Assumptions / FR-143]
- [X] CHK058 - Is the assumption "forgetting the sync password makes remote data unrecoverable; neither developer nor provider can restore it" documented as a user-facing requirement (FR-163), not just an internal limitation? [Assumption, Spec §FR-163]
- [X] CHK059 - Is the external dependency on the Argon2id package documented with selection criteria (maintenance, license, security history, API surface, transitive deps, Swift 6 compatibility, replacement strategy)? [Dependency, Constitution §XIII / research.md R9]
- [X] CHK060 - Is the external dependency on S3-compatible/WebDAV provider behavior (conditional writes, ETag semantics) documented as a compatibility risk with mitigation (manifest serialization)? [Dependency, research.md R10/R11]
- [X] CHK061 - Is the assumption "OCR is not in the initial release but the asset/search model is extensible for later OCR text" documented without implying OCR text enters the durable rich-text format? [Assumption, Spec §Non-goals / data-model §SearchDocument]

## Ambiguities & Conflicts

- [X] CHK062 - Does any requirement conflict between "encrypt all meaningful metadata" (FR-160) and the accepted observable metadata (object sizes, mod times, network addresses) — i.e., is the boundary unambiguous? [Ambiguity/Conflict, Spec §FR-160 vs §Assumptions]
- [X] CHK063 - Is there ambiguity in "one repository at a time" regarding whether replacing a repository must delete the prior remote vault or leave it? [Ambiguity, Spec §FR-154 / Plan §Repository replacement]
- [X] CHK064 - Is there ambiguity in whether "remember unlocked vault on this Mac" (optional) weakens the fail-closed guarantee if the Keychain item is exfiltrated — and is that trade-off documented? [Ambiguity, Plan §Key lifecycle / data-model §VaultConfiguration]
- [X] CHK065 - Is there a potential conflict between "manifest lists object metadata (contentHash, byteSize, modifiedAt)" and "remote must not learn object types" — confirmed that the manifest carries only opaque names + sizes/times, with types encrypted inside objects? [Conflict check, Contracts §encrypted-manifest.schema.json / Spec §FR-161]

## Constitution Alignment (this domain)

- [X] CHK066 - Does every encryption/privacy/sync requirement trace to a constitutional principle (VI privacy, VII encryption, VIII non-destructive sync, IX file references) in the plan's Constitution Check table? [Traceability, Plan §Constitution Check]
- [X] CHK067 - Are the non-negotiable guarantees (fail-closed, no resurrection, no silent overwrite, no file-content sync, no preemptive permission requests) each individually testable as requirements rather than merged into vague statements? [Traceability, Constitution §VII/VIII/IX/VI]
- [X] CHK068 - Is it confirmed that no Complexity Tracking exception is used to bypass encryption, privacy, data integrity, conflict preservation, or destructive-action safety in this domain? [Traceability, Plan §Complexity Tracking / Constitution §Governance]

## Notes

- This checklist tests the **quality of the written requirements**, not whether
  the implementation works. Items phrased as "Are X defined/specified…?" and
  "Is X quantified/clarified…?" validate completeness/clarity/consistency/
  measurability/coverage; they are NOT verification steps.
- Anchors: `[Spec §FR-xxx/SC-xxx]`, `[Plan §<section>]`, `[data-model §<entity>]`,
  `[Contracts §<file>]`, `[Constitution §<principle>]`, `[Gap]` (missing
  requirement), `[Ambiguity]`, `[Conflict]`, `[Assumption]`, `[Dependency]`.
- Focus: encryption / privacy / synchronization safety (constitutional VII/VIII/
  IX/VI). Depth: Standard (PR review gate). Strong traceability: every item
  carries ≥1 reference.
- Items flagged `[Gap]` indicate a requirement that should be added or made
  explicit before `/speckit-tasks`; they are not implementation TODOs.

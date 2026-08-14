import SwiftUI
import AppKit
import Domain
import SyncCore
import SystemBridge

// MARK: - SyncSettingsView (T170/T186/T285; Rev 2 2026-08-14, FR-053/FR-054)
//
// Per tasks.md T170/T186/T285 and spec FR-150/FR-151/FR-152/FR-152a/FR-153/
// FR-154/FR-160/FR-162/FR-162a/FR-163/FR-164/FR-165:
//
// The functional synchronization settings surface, driven by the
// SyncCoordinator (T285): configure/test exactly one WebDAV or S3-compatible
// repository (FR-150), enable/disable automatic sync (FR-152), manual sync
// with explicit non-blocking status (FR-141b/FR-151), last-successful time +
// actionable errors, remove local config WITHOUT deleting local notes
// (FR-151), repository replacement with warning + fresh bootstrap + no
// auto-delete of prior remote data (FR-154), the unrecoverable-password
// warning (FR-163), the FR-162a remember-unlock toggle, and the FR-191
// diagnostic-bundle export (T186).
//
// Rev 2 (2026-08-14, FR-053/FR-054): user-facing hierarchy — Status /
// Storage / Automatic Sync / Security / Actions / Advanced. Status is
// resolver-driven (never the internal "Configured" string); the Locked
// state is shown honestly with an Unlock action; controls that cannot work
// while locked are disabled. Advanced keeps Join as its own product action.
// Status/error feedback is TRANSIENT (auto-clears; never survives a
// Settings close/reopen) and announced via VoiceOver (FR-180b).

public struct SyncSettingsView: View {
    let syncCoordinator: SyncCoordinator?

    @State private var showConfigureSheet = false
    @State private var showJoinSheet = false
    @State private var showReplaceSheet = false
    @State private var showRemoveConfirmation = false
    @State private var showUnlockAlert = false
    @State private var unlockPassword = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    /// Cancels a pending auto-clear when a new transient message arrives
    /// (repeated actions must not let an older message clear the newer one).
    @State private var transientTask: Task<Void, Never>?
    /// Local lightweight copy feedback for the Vault ID affordance (never
    /// routed through the sync transient feedback).
    @State private var vaultIDCopied = false
    @State private var vaultIDCopiedTask: Task<Void, Never>?

    private var isConfigured: Bool { syncCoordinator?.isConfigured == true }
    private var isVaultUnlocked: Bool { syncCoordinator?.isVaultUnlocked == true }
    private var isInProgress: Bool { syncCoordinator?.isInProgress == true }

    /// The active protocol (WebDAV / S3-compatible), or "—" when
    /// unconfigured.
    private var providerText: String {
        switch syncCoordinator?.configuration?.providerType {
        case .webdav: return "WebDAV"
        case .s3: return "S3-compatible"
        case nil: return "—"
        }
    }

    /// Provider-only fallback copy for the degraded Storage display (the
    /// user's original path cannot be recovered reliably).
    private var providerStorageCopy: String {
        switch syncCoordinator?.configuration?.providerType {
        case .webdav: return String(localized: "WebDAV storage")
        case .s3: return String(localized: "S3-compatible storage")
        case nil: return "—"
        }
    }

    public init(syncCoordinator: SyncCoordinator?) {
        self.syncCoordinator = syncCoordinator
    }

    public var body: some View {
        // Rev 2 (FR-051): the Sync pane is the ONE tab that can actually
        // overflow vertically — it owns the scrolling container. Geometry
        // still comes from the window shell, not from this content.
        ScrollView {
            Form {
                if isConfigured {
                    statusSection
                    storageSection
                    automaticSyncSection
                    securitySection
                    advancedSection
                    connectionSection
                } else {
                    notConfiguredSection
                }
                transientFeedback
            }
            .formStyle(.grouped)
            .padding(20)
        }
        // Polish round 3: the system scroll-edge effect (macOS 26+) fades
        // and blurs content at the toolbar boundary — fixes the ghost text
        // under the Liquid Glass tab strip without any opaque overlay.
        .scrollEdgeEffectStyle(.automatic, for: .top)
        .sheet(isPresented: $showConfigureSheet) {
            SyncConfigureSheet(
                syncCoordinator: syncCoordinator,
                title: String(localized: "Set Up Synchronization"),
                onComplete: { status in
                    presentTransient(status, isError: false)
                },
                onError: { error in
                    presentTransient(error, isError: true)
                }
            )
        }
        .sheet(isPresented: $showJoinSheet) {
            SyncConfigureSheet(
                syncCoordinator: syncCoordinator,
                title: String(localized: "Join Existing Vault"),
                startsInJoinMode: true,
                onComplete: { status in
                    presentTransient(status, isError: false)
                },
                onError: { error in
                    presentTransient(error, isError: true)
                }
            )
        }
        .sheet(isPresented: $showReplaceSheet) {
            SyncConfigureSheet(
                syncCoordinator: syncCoordinator,
                title: String(localized: "Set Up New Storage Location"),
                replacing: true,
                onComplete: { status in
                    presentTransient(status, isError: false)
                },
                onError: { error in
                    presentTransient(error, isError: true)
                }
            )
        }
        .confirmationDialog(
            "Disconnect Sync?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task {
                    await syncCoordinator?.removeConfiguration()
                    presentTransient(
                        String(localized: "Sync disconnected. Your notes and the data at the storage location were kept."),
                        isError: false
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stops syncing on this Mac. Your notes and the data at the storage location are kept.")
        }
        .alert("Unlock Vault", isPresented: $showUnlockAlert) {
            SecureField("Vault password", text: $unlockPassword)
            Button("Unlock") {
                Task { await performUnlock() }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                unlockPassword = ""
            }
        } message: {
            Text("Enter your sync password to start syncing on this Mac.")
        }
    }

    // MARK: - Sections

    /// FR-053 + polish round 3: the FIRST row always expresses the current
    /// sync state (resolver-driven — `Up to Date` / error category / locked
    /// / syncing). Manual sync is a state-dependent ACTION, so it lives here
    /// as the trailing control instead of its own empty card; the aged-out
    /// informational note is a weak caption, never the primary status.
    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            if isInProgress {
                Label {
                    Text("Syncing…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
            } else if !isVaultUnlocked {
                LabeledContent {
                    // The restore action is the primary next step while
                    // locked — native prominent, not a big CTA.
                    Button("Unlock…") { showUnlockAlert = true }
                        .buttonStyle(.borderedProminent)
                } label: {
                    Label("Sync vault is locked", systemImage: "lock.fill")
                }
                Text("Unlock the vault to sync manually or resume automatic sync. Your notes on this Mac are still available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent {
                    Button("Sync Now") {
                        Task { await syncCoordinator?.manualSync() }
                    }
                    .buttonStyle(.borderless)
                } label: {
                    if let presentation = resolvedPresentation {
                        Label(presentation.title, systemImage: presentation.symbolName)
                            .foregroundStyle(.orange)
                    } else {
                        Label("Up to Date", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }
                if let detail = resolvedPresentation?.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Last synced") {
                if let date = syncCoordinator?.lastSuccessfulSyncAt {
                    Text(DisplayFormatters.lastModified(date))
                } else {
                    Text("—")
                }
            }
            // FR-174-d (sync.historyAgedOut) is INFORMATIONAL: a weak
            // caption below the primary status, never a substitute for it.
            if syncCoordinator?.lastErrorCode == "sync.historyAgedOut" {
                Label("Some sync history may have aged out; your notes were preserved.", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The FR-012 mapping for the current sync state (nil = healthy).
    /// 003 T058 (FR-011/SC-012): the HUMAN-READABLE mapping — never the raw
    /// internal code (codes stay in the diagnostic export experience only).
    private var resolvedPresentation: SyncStatusPresentation? {
        SyncStatusResolver.resolve(
            isConfigured: true,
            lastErrorCode: syncCoordinator?.lastErrorCode,
            vaultLocked: false,
            hasOfflineChangesPending: false,
            summary: .empty
        )
    }

    /// Rev 2 + polish round 2: user-meaningful storage semantics — which
    /// protocol, and the bucket/prefix or endpoint/prefix the user chose,
    /// with the legacy auto-generated locator segment stripped
    /// (SyncLocationPresentation). Long values middle-truncate and never
    /// drive window width; the full user-semantic value is selectable and
    /// shown in the help tag.
    private var storageSection: some View {
        Section("Storage") {
            if let configuration = syncCoordinator?.configuration {
                LabeledContent("Provider") {
                    Text(providerText)
                }
                LabeledContent("Location") {
                    if let location = SyncLocationPresentation.location(for: configuration) {
                        Text(location)
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .help(location)
                    } else {
                        // Honest degradation (polish round 3): the persisted
                        // prefix does not conform to the user-folder schema
                        // (contains a generated namespace segment) — never
                        // guess a path. The technical path lives in
                        // Advanced (Vault ID help).
                        Text(providerStorageCopy)
                            .foregroundStyle(.secondary)
                            .help(SyncLocationPresentation.technicalPath(for: configuration))
                    }
                }

                // FR-054 (Rev 3, T186): vault/storage management lives in a
                // "Manage…" menu here — INDEPENDENT actions (join stays its
                // own product action, CHK033 re-entry preserved), never
                // merged into one flow.
                Menu {
                    Button("Join Another Vault…") {
                        showJoinSheet = true
                    }
                    .help("Connects this Mac to a vault created on another Mac. Your local notes are preserved.")
                    Button("Set Up New Storage Location…") {
                        showReplaceSheet = true
                    }
                    .help("Creates a new vault at a new storage location. Local notes are preserved; the previous location's data is not deleted.")
                } label: {
                    Text("Manage…")
                }
                .help("Manage the vault or its storage location")
            }
        }
    }

    private var automaticSyncSection: some View {
        Section("Automatic Sync") {
            Toggle("Sync changes automatically", isOn: Binding(
                get: { syncCoordinator?.autoSyncEnabled ?? false },
                set: { syncCoordinator?.setAutoSyncEnabled($0) }
            ))
            .help(isVaultUnlocked
                ? "Syncs automatically a few seconds after local changes"
                : "Automatic sync starts once the vault is unlocked on this Mac.")

            // FR-152 (clarified 2026-08-08): user-selectable strategy —
            // change-only or a fixed periodic interval. Rev 3 (T185): the
            // row is named "Periodic sync" (the picker axis) with change-only
            // shown as "Off"; the schedule is a device-local preference, so
            // a LOCKED vault does not disable it — only the master switch
            // above does (FR-053 Rev 3).
            Picker("Periodic sync", selection: Binding(
                get: { syncCoordinator?.autoSyncPolicy ?? .default },
                set: { syncCoordinator?.setAutoSyncPolicy($0) }
            )) {
                ForEach(AutoSyncPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            .pickerStyle(.menu)
            .disabled(!(syncCoordinator?.autoSyncEnabled ?? false))
            .help("When automatic sync is on: sync after local changes only, or also on a fixed interval")

            // Polish round 2/3: describe the behavior WHEN enabled. The
            // 2-4 s debounce is an implementation detail; the copy that
            // matters is "automatic" + "periodic is optional" (true for
            // every policy, including change-only).
            Text("When enabled, changes sync automatically. Periodic syncing is optional.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// FR-162a (Rev 2 copy): the toggle renames the internal
    /// "remember-unlock" mechanism to user semantics. Verified behavior:
    /// the VAULT KEY (not the password) is stored in Keychain and cleared on
    /// restart or explicit lock.
    private var securitySection: some View {
        Section("Security") {
            Toggle("Keep sync unlocked on this Mac", isOn: Binding(
                get: { (syncCoordinator?.configuration?.rememberedUnlock ?? .disabled) == .enabledUntilLockOrRestart },
                set: { newValue in
                    Task {
                        do {
                            try await syncCoordinator?.setRememberUnlock(newValue)
                            presentTransient(
                                newValue
                                    ? String(localized: "Sync will stay unlocked on this Mac until it restarts or you lock the vault.")
                                    : String(localized: "The remembered unlock was cleared."),
                                isError: false
                            )
                        } catch {
                            presentTransient(String(localized: "Could not change the remember-unlock setting."), isError: true)
                        }
                    }
                }
            ))
            .disabled(!isVaultUnlocked)
            .help("Keeps the vault unlocked across app relaunches until this Mac restarts or you lock the vault.")
            Text("Keeps sync unlocked using Keychain until you restart or lock the vault.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // FR-163 (Rev 3, T186): the no-recovery warning is a SECURITY
            // decision, not an advanced detail — its info row lives here,
            // concise standard style, never dominating the pane.
            VStack(alignment: .leading, spacing: 4) {
                Text("Recovery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("There is no password recovery. If you forget your sync password, your encrypted sync data can't be recovered.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    /// FR-054 (Rev 3, T186): the Advanced area holds the TECHNICAL
    /// operations only, in a default-collapsed disclosure (system
    /// DisclosureGroup — VoiceOver announces expanded/collapsed, Reduce
    /// Motion unaffected). Vault/storage management moved to the Storage
    /// "Manage…" menu; Disconnect Sync… is the standalone entry below.
    private var advancedSection: some View {
        Section {
            DisclosureGroup {
                advancedContent
            } label: {
                Text("Advanced")
            }
        }
    }

    /// The disclosure content: the technical subset only — Vault ID
    /// (copyable) + the two exports. `.buttonStyle(.link)` — the system
    /// link presentation (accent color, hover/focus, keyboard reachable).
    @ViewBuilder
    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Vault ID (copyable) — its own row.
            if let configuration = syncCoordinator?.configuration {
                vaultIDRow(
                    configuration.vaultLocator,
                    technicalPath: SyncLocationPresentation.location(for: configuration) == nil
                        ? SyncLocationPresentation.technicalPath(for: configuration)
                        : nil
                )
            }

            Divider()
                .padding(.vertical, 6)

            // Export / Support
            // FR-009/US2 (T016): export the sync profile (schema v2,
            // no secrets) so another Mac can join this vault.
            Button("Export Sync Profile…") {
                exportSyncProfile()
            }
            .buttonStyle(.link)
            .help("Saves a sync profile for another Mac. Contains no credentials, keys, or note content.")

            // FR-191 (T186): diagnostic bundle export.
            Button("Export Diagnostic Bundle…") {
                exportDiagnosticBundle()
            }
            .buttonStyle(.link)
            .help("Saves a sanitized diagnostics JSON for support. No note content or credentials are included.")
        }
        .padding(.vertical, 4)
    }

    /// FR-054 (Rev 3, T186): Disconnect Sync… is a STANDALONE destructive
    /// entry at the bottom of the pane — confirmed (role: .destructive
    /// dialog), visually/semantically distinct, never buried in the
    /// technical area.
    private var connectionSection: some View {
        Section {
            Button("Disconnect Sync…", role: .destructive) {
                showRemoveConfirmation = true
            }
            .buttonStyle(.link)
            .help("Stops syncing on this Mac. Your notes and the data at the storage location are kept.")
        }
    }

    /// FR-008/US1: the vault locator is the join key for another Mac
    /// (manual entry fallback when scan/profile import are unavailable).
    /// Opaque and non-sensitive (CHK032). Polish round 3: ACTIVE
    /// presentation shortening (a fixed short form — overflow truncation
    /// never triggers when the row has room); Copy always copies the full
    /// ID; the help tag shows the full ID (plus the technical path when the
    /// Storage display degraded).
    private func vaultIDRow(_ locator: String, technicalPath: String?) -> some View {
        HStack(spacing: 8) {
            Text("Vault ID")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(VaultIDPresentation.abbreviated(locator))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .help(helpTextForVaultID(locator, technicalPath: technicalPath))
            Button {
                copyVaultID(locator)
            } label: {
                Image(systemName: vaultIDCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel("Copy Vault ID")
            .help("Copy Vault ID")
        }
    }

    /// Full-ID tooltip; appends the technical path when the default Storage
    /// display degraded (the user's original folder could not be recovered).
    private func helpTextForVaultID(_ locator: String, technicalPath: String?) -> String {
        if let technicalPath {
            return "\(locator)\n\(String(localized: "Technical path: \(technicalPath)"))"
        }
        return locator
    }

    /// Local copy feedback: clipboard + VoiceOver announcement + a brief
    /// checkmark swap on the button. Deliberately NOT `presentTransient`
    /// (that surface carries sync operation results — a clipboard action
    /// must not overwrite them or trigger the sync banner).
    private func copyVaultID(_ locator: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(locator, forType: .string)
        AccessibilityAnnouncements.announce(String(localized: "Copied."))
        vaultIDCopiedTask?.cancel()
        vaultIDCopied = true
        vaultIDCopiedTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            vaultIDCopied = false
        }
    }

    /// Unconfigured state: both initial-setup paths (FR-054 + clarify 4,
    /// CHK006/CHK033) — joining is discoverable without an advanced area.
    private var notConfiguredSection: some View {
        Section {
            LabeledContent("Status") {
                Text("Not configured")
                    .foregroundStyle(.secondary)
            }
            Text("Sync keeps your notes available on all your Macs through a WebDAV or S3-compatible storage location. Your notes are encrypted on this Mac before upload. Your storage provider receives only encrypted note data.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Set Up Sync…") {
                showConfigureSheet = true
            }
            Button("Join Existing Vault…") {
                showJoinSheet = true
            }
            .help("Joins a vault created on another Mac. Your local notes are preserved.")
        }
    }

    /// Rev 2: transient feedback — appears after an action, auto-clears,
    /// never survives a Settings close/reopen.
    @ViewBuilder
    private var transientFeedback: some View {
        if let statusMessage {
            Label(statusMessage, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    /// Presents a transient status/error message: cancels any pending
    /// auto-clear, announces via VoiceOver (FR-180b), and schedules the
    /// auto-clear.
    private func presentTransient(_ message: String, isError: Bool) {
        transientTask?.cancel()
        if isError {
            statusMessage = nil
            errorMessage = message
        } else {
            errorMessage = nil
            statusMessage = message
        }
        AccessibilityAnnouncements.announce(message)
        transientTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            statusMessage = nil
            errorMessage = nil
        }
    }

    /// Rev 2 (FR-162a(b)/FR-053): unlock the locked vault with the sync
    /// password (read-only remote bootstrap fetch + existing crypto
    /// primitives). Sanitized, distinguishable failure codes.
    private func performUnlock() async {
        let password = unlockPassword
        unlockPassword = ""
        do {
            try await syncCoordinator?.unlock(password: password)
            presentTransient(String(localized: "Vault unlocked. Syncing is available on this Mac."), isError: false)
        } catch {
            let code: String
            if let sticky = error as? StickyError {
                switch sticky {
                case .encryption(.wrongPassword):
                    code = "wrong-password"
                case .credentials(.notFound):
                    code = "vault-not-found"
                default:
                    code = sticky.sanitizedCode
                }
            } else {
                code = "unlock-failed"
            }
            presentTransient(String(localized: "Could not unlock the vault: \(code)."), isError: true)
        }
    }

    private static func profileFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "stickynotes-sync-profile-\(formatter.string(from: Date())).json"
    }

    /// T016 (FR-009/US2/AC1): writes a schema-v2 sync profile (protocol,
    /// locator, origin device name, redacted provider config) via NSSavePanel.
    /// NEVER credentials/keys/content (SC-004/CHK029); the filename is
    /// opaque + dated (FR-191 sanitized boundary).
    private func exportSyncProfile() {
        guard let configuration = syncCoordinator?.configuration else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = Self.profileFileName()
        panel.message = String(localized: "Save a sync profile to join this vault from another Mac.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // T032: the suite version comes from the actual vault (never
            // hardcoded); encode throws instead of writing an empty file.
            let wire = try SyncProfileCodec.encode(
                providerType: configuration.providerType,
                vaultId: configuration.vaultId,
                vaultLocator: configuration.vaultLocator,
                providerConfig: configuration.providerConfig,
                encryptionSuiteVersion: syncCoordinator?.encryptionSuiteVersion ?? 1,
                originDeviceName: AppDevice.current().displayName
            )
            try wire.write(to: url, options: .atomic)
            presentTransient(String(localized: "Sync profile exported. No credentials or note content are included."), isError: false)
        } catch {
            presentTransient(String(localized: "Could not export the sync profile."), isError: true)
        }
    }

    /// T186 (FR-191): generates the diagnostic bundle via T185
    /// (DiagnosticBundleGenerator) and presents a save panel so the user can
    /// save/share the JSON for support. The filename is opaque
    /// (`stickynotes-diagnostics-<date>.json`); the exported file contains
    /// ONLY the FR-191-enumerated fields (never note content, paths,
    /// credentials, or raw server responses).
    private func exportDiagnosticBundle() {
        let objectCounts = DiagnosticObjectCounts()
        let bundle = DiagnosticBundleGenerator.generate(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            schemaVersionLocal: 2,
            providerType: syncCoordinator?.configuration?.providerType,
            recentErrorEvents: [],
            syncRunCounts: nil,
            objectCounts: objectCounts,
            vaultState: syncCoordinator?.isConfigured == true ? .unlocked : .unconfigured,
            permissionStatuses: DiagnosticPermissionStatuses(
                screenRecording: PermissionService.screenRecordingGranted,
                accessibility: PermissionService.accessibilityStatus() == .granted
            )
        )
        guard let data = try? DiagnosticBundleGenerator.encode(bundle) else {
            presentTransient(String(localized: "Could not generate the diagnostic bundle."), isError: true)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "stickynotes-diagnostics-\(formatter.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            presentTransient(String(localized: "Diagnostic bundle exported. It contains no note content or credentials."), isError: false)
        } catch {
            presentTransient(String(localized: "Could not save the diagnostic bundle."), isError: true)
        }
    }
}

// MARK: - Configure / replace sheet (FR-150/FR-151/FR-154)

/// The configure/replace/join repository form: mode picker (create/join),
/// provider type, endpoint + container/bucket, credentials, vault password,
/// remember-unlock, and (join mode) vault locator + import-from-file.
private struct SyncConfigureSheet: View {
    let syncCoordinator: SyncCoordinator?
    let title: String
    var replacing = false
    /// T029: open the sheet already in join mode (the configured-state
    /// "Join Another Vault…" entry point). Non-replacing create sheets
    /// default to create mode.
    var startsInJoinMode = false
    let onComplete: (String) -> Void
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// FR-001: create-new-vault vs join-existing-vault mode.
    private enum JoinMode: String, CaseIterable {
        case create
        case join
    }

    @State private var mode: JoinMode = .create
    @State private var providerType: ProviderType = .webdav
    @State private var endpoint = ""
    @State private var containerPath = ""
    @State private var bucket = ""
    @State private var region = "us-east-1"
    @State private var username = ""
    @State private var password = ""
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var vaultLocator = ""
    @State private var originDeviceName: String?
    /// T028/CHK025: the imported profile's vaultId — the user's stated
    /// expectation. Joining a location whose bootstrap is a DIFFERENT vault
    /// fails closed (wrong-vault), while manual locator entry (no profile)
    /// is free to join any vault (US1/AC6 replace semantics).
    @State private var expectedVaultId: UUID?
    /// Scan-before-join state (discoverVaults): discovered vaults, the
    /// selected one, and scan progress/errors.
    @State private var discoveredVaults: [DiscoveredVault] = []
    @State private var selectedVaultId: UUID?
    @State private var isScanning = false
    @State private var didScan = false
    @State private var scanError: String?
    @State private var vaultPassword = ""
    @State private var confirmVaultPassword = ""
    @State private var rememberUnlock = false
    @State private var isTesting = false
    @State private var isConfiguring = false
    /// In-sheet status: success vs failure (the "Connection OK." message must
    /// use a success icon, not the orange warning used for errors).
    @State private var sheetStatus: (message: String, isError: Bool)?

    init(
        syncCoordinator: SyncCoordinator?,
        title: String,
        replacing: Bool = false,
        startsInJoinMode: Bool = false,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.syncCoordinator = syncCoordinator
        self.title = title
        self.replacing = replacing
        self.startsInJoinMode = startsInJoinMode
        self.onComplete = onComplete
        self.onError = onError
        if startsInJoinMode {
            _mode = State(initialValue: .join)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.bold())

            if !replacing {
                Picker("Mode", selection: $mode) {
                    Text("Create new vault").tag(JoinMode.create)
                    Text("Join existing vault").tag(JoinMode.join)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Synchronization mode")
            }

            Picker("Provider", selection: $providerType) {
                Text("WebDAV").tag(ProviderType.webdav)
                Text("S3-compatible").tag(ProviderType.s3)
            }
            .pickerStyle(.segmented)

            Group {
                switch providerType {
                case .webdav:
                    TextField("Server URL (https://…)", text: $endpoint)
                    TextField("Container path (optional)", text: $containerPath)
                    TextField("Username (optional)", text: $username)
                    SecureField("Password (optional)", text: $password)
                case .s3:
                    TextField("Endpoint URL (https://…)", text: $endpoint)
                    TextField("Bucket", text: $bucket)
                    TextField("Region", text: $region)
                    // FR-150 / clarified 2026-08-08: optional folder/prefix —
                    // objects are stored under "<prefix>/<vault-locator>/".
                    TextField("Folder / Prefix (optional)", text: $containerPath)
                    TextField("Access key", text: $accessKey)
                    SecureField("Secret key", text: $secretKey)
                }
            }
            .textFieldStyle(.roundedBorder)

            if mode == .join {
                Divider()

                // Scan-before-join: list existing vaults on the configured
                // repository so the user picks one instead of typing the
                // opaque locator.
                HStack {
                    Button("Scan for Existing Vaults…") {
                        Task { await scanForVaults() }
                    }
                    .disabled(isScanning || !isProviderFormValid)
                    .accessibilityLabel("Scan the repository for existing vaults")
                    if isScanning {
                        ProgressView().controlSize(.small)
                    }
                }
                if scanError != nil {
                    Label(scanError!, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Vault scan error")
                }
                if !discoveredVaults.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Existing vaults")
                            .font(.subheadline.bold())
                        ForEach(discoveredVaults) { vault in
                            Button {
                                selectDiscoveredVault(vault)
                            } label: {
                                HStack {
                                    Image(systemName: "lock.rectangle.stack.fill")
                                    VStack(alignment: .leading) {
                                        Text("Vault · \(DisplayFormatters.absoluteDate(vault.createdAt))")
                                        Text(String(vault.vaultLocator.prefix(12)) + "…")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospaced()
                                    }
                                    Spacer()
                                    if vault.id == selectedVaultId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Join vault created on \(DisplayFormatters.absoluteDate(vault.createdAt))")
                        }
                    }
                } else if !didScan && !isScanning {
                    Text("No vaults scanned yet — scan the repository to pick an existing vault, or enter the locator manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    TextField("Vault locator", text: $vaultLocator)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Vault locator")
                        .onChange(of: vaultLocator) { _, _ in
                            originDeviceName = nil
                            selectedVaultId = nil
                        }
                    Button("Import from file…") { importProfile() }
                        .accessibilityLabel("Import sync profile from file")
                }
                // CHK024 (T030): the format pre-check surfaces a visible
                // message when the locator is non-empty but malformed —
                // the Join button is disabled AND the user is told why.
                if !vaultLocator.isEmpty && !isLocatorFormatValid(vaultLocator) {
                    Label("Vault locator format is invalid (expected 32 hex characters).", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Vault locator format error")
                }
                if let originDeviceName {
                    Label("From: \(originDeviceName)", systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Sync profile origin device: \(originDeviceName)")
                }
            }

            Divider()

            Text(mode == .join ? "Vault password" : "Vault password (new)")
                .font(.headline)
            Text("The vault password encrypts your notes. If you forget it, your synced notes cannot be recovered.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Vault password", text: $vaultPassword)
                .textFieldStyle(.roundedBorder)
            if mode == .create {
                SecureField("Confirm vault password", text: $confirmVaultPassword)
                    .textFieldStyle(.roundedBorder)
            }
            if mode == .create {
                Toggle("Keep sync unlocked on this Mac", isOn: $rememberUnlock)
            }

            if let sheetStatus {
                Label(
                    sheetStatus.message,
                    systemImage: sheetStatus.isError
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(sheetStatus.isError ? .orange : .green)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Test Connection") {
                    Task { await testConnection() }
                }
                .disabled(isTesting || isConfiguring)
                Button(isConfiguring ? "Working…" : (replacing || mode == .create ? "Set Up" : "Join")) {
                    Task { await configureOrJoin() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isTesting || isConfiguring || !isFormValid)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var isFormValid: Bool {
        guard !endpoint.trimmingCharacters(in: .whitespaces).isEmpty,
              !vaultPassword.isEmpty else { return false }
        if mode == .create {
            guard vaultPassword == confirmVaultPassword else { return false }
        }
        if mode == .join {
            // CHK024: the locator is pre-validated before the join is
            // attempted — opaque 32-hex shape (format error surfaced inline).
            guard isLocatorFormatValid(vaultLocator) else { return false }
        }
        switch providerType {
        case .webdav: return true
        case .s3: return !bucket.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// CHK024: locator format pre-check — 32 hex chars (the opaque locator
    /// shape generated by `RemoteLayout.opaqueObjectName()`).
    private func isLocatorFormatValid(_ locator: String) -> Bool {
        let trimmed = locator.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 32 && trimmed.allSatisfy { $0.isHexDigit }
    }

    /// The provider fields needed before a scan/join can run.
    private var isProviderFormValid: Bool {
        guard !endpoint.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch providerType {
        case .webdav: return true
        case .s3: return !bucket.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Scans the configured repository for existing vaults (discoverVaults)
    /// so the user can pick one to join instead of typing the locator.
    private func scanForVaults() async {
        isScanning = true
        scanError = nil
        defer { isScanning = false }
        do {
            let vaults = try await syncCoordinator?.discoverVaults(
                providerType: providerType,
                endpoint: endpoint,
                containerPath: containerPath,
                bucket: bucket,
                region: region,
                credentials: credentials
            ) ?? []
            discoveredVaults = vaults
            didScan = true
            if vaults.isEmpty {
                scanError = String(localized: "No existing vaults found in this repository.")
            }
        } catch {
            scanError = String(localized: "Could not scan the repository: \((error as? StickyError)?.sanitizedCode ?? "unavailable").")
        }
    }

    /// Fills the join form from a discovered vault (locator + expected id).
    private func selectDiscoveredVault(_ vault: DiscoveredVault) {
        vaultLocator = vault.vaultLocator
        expectedVaultId = vault.vaultId
        originDeviceName = nil
        selectedVaultId = vault.id
        scanError = nil
    }

    /// FR-010/US2: imports a sync-profile file (v1/v2) and fills provider
    /// type + locator; shows the origin device name. Fail closed on
    /// corrupt/unsupported files (no local config written).
    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose a sync profile exported from another Mac.")
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        do {
        let profile = try SyncProfileCodec.decode(data)
        providerType = profile.providerType
        endpoint = profile.providerConfig.endpoint
        bucket = profile.providerConfig.bucket ?? ""
        region = profile.providerConfig.region ?? "us-east-1"
        containerPath = profile.providerConfig.prefix ?? ""
        vaultLocator = profile.vaultLocator
        originDeviceName = profile.originDeviceName
        expectedVaultId = profile.vaultId
        sheetStatus = (String(localized: "Sync profile imported. Enter the vault password to join."), false)
        } catch {
            sheetStatus = (String(localized: "This file is not a valid sync profile (unsupported or corrupted)."), true)
        }
    }

    /// FR-151: tests connectivity + credentials without configuring.
    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        do {
            try await syncCoordinator?.testConnection(
                providerType: providerType,
                endpoint: endpoint,
                containerPath: containerPath,
                bucket: bucket,
                region: region,
                credentials: credentials
            )
            sheetStatus = (String(localized: "Connection OK."), false)
        } catch {
            sheetStatus = (
                String(localized: "Connection failed: \((error as? StickyError)?.sanitizedCode ?? "unavailable")."),
                true
            )
        }
    }

    private func configureOrJoin() async {
        if mode == .join {
            await join()
        } else {
            await configure()
        }
    }

    /// US1 (FR-002/FR-003/FR-004/FR-005): joins a vault created on another
    /// device. Fail closed: wrong password / missing vault never write a
    /// local config or modify remote data.
    private func join() async {
        isConfiguring = true
        defer { isConfiguring = false }
        do {
            try await syncCoordinator?.joinExistingVault(
                providerType: providerType,
                endpoint: endpoint,
                containerPath: containerPath,
                bucket: bucket,
                region: region,
                vaultLocator: vaultLocator.trimmingCharacters(in: .whitespacesAndNewlines),
                credentials: credentials,
                vaultPassword: vaultPassword,
                expectedVaultId: expectedVaultId
            )
            onComplete(String(localized: "Joined the existing vault and completed the first sync."))
            dismiss()
        } catch {
            // FR-004/FR-005/CHK028: distinguishable, sanitized codes.
            let code: String
            if let sticky = error as? StickyError {
                switch sticky {
                case .credentials(.notFound):
                    code = "vault-not-found"
                case .credentials(.wrongVault):
                    code = "wrong-vault"
                case .encryption(.wrongPassword):
                    code = "wrong-password"
                default:
                    code = sticky.sanitizedCode
                }
            } else {
                code = "join-failed"
            }
            onError(String(localized: "Could not join the vault: \(code)."))
        }
    }

    private func configure() async {
        isConfiguring = true
        defer { isConfiguring = false }
        do {
            if replacing {
                try await syncCoordinator?.replaceRepository(
                    providerType: providerType,
                    endpoint: endpoint,
                    containerPath: containerPath,
                    bucket: bucket,
                    region: region,
                    credentials: credentials,
                    vaultPassword: vaultPassword
                )
                onComplete(String(localized: "A new vault was created at the new storage location. Your local notes were kept; the old location's data was not deleted."))
            } else {
                try await syncCoordinator?.configure(
                    providerType: providerType,
                    endpoint: endpoint,
                    containerPath: containerPath,
                    bucket: bucket,
                    region: region,
                    credentials: credentials,
                    vaultPassword: vaultPassword,
                    rememberUnlock: rememberUnlock
                )
                onComplete(String(localized: "Synchronization configured and first sync completed."))
            }
            dismiss()
        } catch {
            onError(String(localized: "Configuration failed: \((error as? StickyError)?.sanitizedCode ?? "unavailable")."))
        }
    }

    private var credentials: SyncProviderCredentials {
        SyncProviderCredentials(
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password,
            accessKey: accessKey.isEmpty ? nil : accessKey,
            secretKey: secretKey.isEmpty ? nil : secretKey
        )
    }
}

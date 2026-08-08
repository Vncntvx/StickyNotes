import SwiftUI
import AppKit
import Domain
import SyncCore
import SystemBridge

// MARK: - SyncSettingsView (T170/T186/T285)
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

public struct SyncSettingsView: View {
    let syncCoordinator: SyncCoordinator?

    @State private var showConfigureSheet = false
    @State private var showJoinSheet = false
    @State private var showReplaceSheet = false
    @State private var showRemoveConfirmation = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    /// The configured status, including the active protocol so the user can
    /// always see which sync protocol is in use (FR-150).
    private var statusText: String {
        guard syncCoordinator?.isConfigured == true else { return "Not configured" }
        return "Configured"
    }

    /// The active protocol (WebDAV / S3-compatible), or "—" when
    /// unconfigured.
    private var providerText: String {
        switch syncCoordinator?.configuration?.providerType {
        case .webdav: return "WebDAV"
        case .s3: return "S3-compatible"
        case nil: return "—"
        }
    }

    /// The configured repository address (endpoint + bucket/prefix, no
    /// credentials) — lets the user verify WHERE their vault lives.
    private func repositoryText(_ configuration: VaultConfiguration) -> String {
        let config = configuration.providerConfig
        switch configuration.providerType {
        case .webdav:
            return config.prefix.map { "\(config.endpoint)/\($0)" } ?? config.endpoint
        case .s3:
            if let bucket = config.bucket {
                if let prefix = config.prefix, !prefix.isEmpty {
                    return "\(bucket)/\(prefix)"
                }
                return bucket
            }
            return config.endpoint
        }
    }

    public init(syncCoordinator: SyncCoordinator?) {
        self.syncCoordinator = syncCoordinator
    }

    public var body: some View {
        Form {
            Section("Synchronization") {
                Text("Sticky Notes syncs end-to-end encrypted to exactly one WebDAV or S3-compatible repository. Content is encrypted on this Mac before upload.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LabeledContent("Status") {
                    Text(statusText)
                }
                LabeledContent("Provider") {
                    Text(providerText)
                }
                if let configuration = syncCoordinator?.configuration {
                    // FR-008/US1: the vault locator is the join key for
                    // another Mac (manual entry or exported profile). Opaque
                    // and non-sensitive (CHK032); displayed so device A can
                    // share it with device B.
                    LabeledContent("Vault") {
                        Text(configuration.vaultLocator)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .help("The vault locator. Enter it on another Mac to join this vault.")
                    }
                    LabeledContent("Repository") {
                        Text(repositoryText(configuration))
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Last successful sync") {
                    if let date = syncCoordinator?.lastSuccessfulSyncAt {
                        Text(DisplayFormatters.lastModified(date))
                    } else {
                        Text("—")
                    }
                }
                if let error = syncCoordinator?.lastErrorCode {
                    // FR-174-d (sync.historyAgedOut) is INFORMATIONAL, not an
                    // error: some sync history may have aged out; content is
                    // preserved. Show it muted instead of the alarming orange.
                    if error == "sync.historyAgedOut" {
                        LabeledContent("Sync history") {
                            Text("Some sync history may have aged out; your notes were preserved.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent("Last error") {
                            Text(error)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if syncCoordinator?.isConfigured == true {
                    Toggle("Automatic sync", isOn: Binding(
                        get: { syncCoordinator?.autoSyncEnabled ?? false },
                        set: { syncCoordinator?.setAutoSyncEnabled($0) }
                    ))
                    .help("Syncs automatically a few seconds after local changes (FR-152a)")

                    // FR-152 (clarified 2026-08-08): user-selectable strategy —
                    // change-only or a fixed periodic interval.
                    Picker("Sync frequency", selection: Binding(
                        get: { syncCoordinator?.autoSyncPolicy ?? .default },
                        set: { syncCoordinator?.setAutoSyncPolicy($0) }
                    )) {
                        ForEach(AutoSyncPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!(syncCoordinator?.autoSyncEnabled ?? false))
                    .help("When automatic sync is on: sync after local changes only, or also on a fixed interval (FR-152)")

                    Toggle("Remember unlocked vault on this Mac", isOn: Binding(
                        get: { (syncCoordinator?.configuration?.rememberedUnlock ?? .disabled) == .enabledUntilLockOrRestart },
                        set: { newValue in
                            Task {
                                do {
                                    try await syncCoordinator?.setRememberUnlock(newValue)
                                    statusMessage = newValue
                                        ? String(localized: "Unlock will be remembered until this Mac restarts or you lock the vault.")
                                        : String(localized: "Remembered unlock cleared.")
                                } catch {
                                    errorMessage = String(localized: "Could not change the remember-unlock setting.")
                                }
                            }
                        }
                    ))

                    Button {
                        Task {
                            await syncCoordinator?.manualSync()
                        }
                    } label: {
                        if syncCoordinator?.isInProgress == true {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Syncing…")
                            }
                        } else {
                            Text("Sync Now")
                        }
                    }
                }
            }

            Section {
                if syncCoordinator?.isConfigured == true {
                    // FR-002/US1/AC6 (T029): joining a DIFFERENT existing
                    // vault from the configured state applies replace
                    // semantics — the mode picker stays available.
                    Button("Join Existing Vault…") {
                        showJoinSheet = true
                    }
                    .help("Joins a vault created on another Mac. Your local notes are preserved.")
                    Button("Replace Repository…", role: .destructive) {
                        showReplaceSheet = true
                    }
                    .help("Configures a new repository. Local notes are preserved; the prior repository's remote data is not deleted.")
                    Button("Remove Configuration…", role: .destructive) {
                        showRemoveConfirmation = true
                    }
                    .help("Removes the local sync configuration. Local notes are NOT deleted.")
                    // FR-009/US2 (T016): export the sync profile (schema v2,
                    // no secrets) so another Mac can join this vault.
                    Button("Export Sync Profile…") {
                        exportSyncProfile()
                    }
                    .help("Saves a sync profile for another Mac. Contains no credentials, keys, or note content.")
                } else {
                    Button("Configure Sync…") {
                        showConfigureSheet = true
                    }
                }

                // FR-163: unrecoverable-password warning.
                Label("If you forget your sync password, your synced notes cannot be recovered. Neither the developer nor the storage provider can restore them.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)

                // FR-191 (T186): diagnostic bundle export.
                Button("Export Diagnostic Bundle…") {
                    exportDiagnosticBundle()
                }
                .help("Saves a sanitized diagnostics JSON for support. No note content or credentials are included.")
            }

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
        .formStyle(.grouped)
        .padding(20)
        .sheet(isPresented: $showConfigureSheet) {
            SyncConfigureSheet(
                syncCoordinator: syncCoordinator,
                title: String(localized: "Configure Synchronization"),
                onComplete: { status in
                    statusMessage = status
                    errorMessage = nil
                },
                onError: { error in
                    errorMessage = error
                }
            )
        }
        .sheet(isPresented: $showJoinSheet) {
            SyncConfigureSheet(
                syncCoordinator: syncCoordinator,
                title: String(localized: "Join Existing Vault"),
                startsInJoinMode: true,
                onComplete: { status in
                    statusMessage = status
                    errorMessage = nil
                },
                onError: { error in
                    errorMessage = error
                }
            )
        }
        .sheet(isPresented: $showReplaceSheet) {
            SyncConfigureSheet(
                syncCoordinator: syncCoordinator,
                title: String(localized: "Replace Repository"),
                replacing: true,
                onComplete: { status in
                    statusMessage = status
                    errorMessage = nil
                },
                onError: { error in
                    errorMessage = error
                }
            )
        }
        .confirmationDialog(
            "Remove sync configuration?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Configuration", role: .destructive) {
                Task {
                    await syncCoordinator?.removeConfiguration()
                    statusMessage = String(localized: "Sync configuration removed. Your local notes were kept.")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Local notes are preserved. Remote data in the previous repository is not deleted — cleaning it up is your responsibility.")
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
            statusMessage = String(localized: "Sync profile exported. No credentials or note content are included.")
        } catch {
            errorMessage = String(localized: "Could not export the sync profile.")
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
            statusMessage = String(localized: "Could not generate the diagnostic bundle.")
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
            statusMessage = String(localized: "Diagnostic bundle exported. It contains no note content or credentials.")
        } catch {
            statusMessage = String(localized: "Could not save the diagnostic bundle.")
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
    /// "Join Existing Vault…" entry point). Non-replacing create sheets
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
                HStack {
                    TextField("Vault locator", text: $vaultLocator)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Vault locator")
                        .onChange(of: vaultLocator) { _, _ in
                            originDeviceName = nil
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
                Toggle("Remember unlocked vault on this Mac", isOn: $rememberUnlock)
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
                Button(isConfiguring ? "Working…" : (replacing ? "Replace" : (mode == .join ? "Join" : "Configure"))) {
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
                onComplete(String(localized: "Repository replaced. Local notes were preserved; the prior repository's remote data was not deleted."))
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

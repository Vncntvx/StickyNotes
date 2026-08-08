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
                LabeledContent("Last successful sync") {
                    if let date = syncCoordinator?.lastSuccessfulSyncAt {
                        Text(DisplayFormatters.lastModified(date))
                    } else {
                        Text("—")
                    }
                }
                if let error = syncCoordinator?.lastErrorCode {
                    LabeledContent("Last error") {
                        Text(error)
                            .foregroundStyle(.orange)
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
                    Button("Replace Repository…", role: .destructive) {
                        showReplaceSheet = true
                    }
                    .help("Configures a new repository. Local notes are preserved; the prior repository's remote data is not deleted.")
                    Button("Remove Configuration…", role: .destructive) {
                        showRemoveConfirmation = true
                    }
                    .help("Removes the local sync configuration. Local notes are NOT deleted.")
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

/// The configure/replace repository form: provider type, endpoint +
/// container/bucket, credentials, vault password, remember-unlock.
private struct SyncConfigureSheet: View {
    let syncCoordinator: SyncCoordinator?
    let title: String
    var replacing = false
    let onComplete: (String) -> Void
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var providerType: ProviderType = .webdav
    @State private var endpoint = ""
    @State private var containerPath = ""
    @State private var bucket = ""
    @State private var region = "us-east-1"
    @State private var username = ""
    @State private var password = ""
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var vaultPassword = ""
    @State private var confirmVaultPassword = ""
    @State private var rememberUnlock = false
    @State private var isTesting = false
    @State private var isConfiguring = false
    /// In-sheet status: success vs failure (the "Connection OK." message must
    /// use a success icon, not the orange warning used for errors).
    @State private var sheetStatus: (message: String, isError: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.bold())

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

            Divider()

            Text("Vault password (new)")
                .font(.headline)
            Text("The vault password encrypts your notes. If you forget it, your synced notes cannot be recovered.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Vault password", text: $vaultPassword)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirm vault password", text: $confirmVaultPassword)
                .textFieldStyle(.roundedBorder)
            Toggle("Remember unlocked vault on this Mac", isOn: $rememberUnlock)

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
                Button(isConfiguring ? "Working…" : (replacing ? "Replace" : "Configure")) {
                    Task { await configure() }
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
              !vaultPassword.isEmpty,
              vaultPassword == confirmVaultPassword else { return false }
        switch providerType {
        case .webdav: return true
        case .s3: return !bucket.trimmingCharacters(in: .whitespaces).isEmpty
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

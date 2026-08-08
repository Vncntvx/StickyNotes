import Foundation
import Domain
import SyncCore
import SwiftUI

// MARK: - SyncStatusPresentation (003 T055, FR-012/CHK002)
//
// Per tasks.md T055 and spec FR-012 (clarify 1): a deterministic PURE-
// FUNCTION mapping from the engine's internal state to the seven
// user-facing categories (each with title/detail/action/dismissible per
// data-model.md). Inputs: SyncCoordinator state + SyncSummary flags +
// sanitized ProviderError codes. Multi-category priority (CHK002):
// ⑦>③>②>①>⑤>④>⑥ (plan.md §9). `viewConflicts` reuses the existing
// conflict-copy note window (001 ConflictCopyView/NoteWindowCoordinator —
// no new view).

/// The seven user-facing sync attention categories (FR-012).
public enum SyncStatusCategory: String, Sendable, CaseIterable, Equatable {
    case cannotConnect        // ① 无法连接仓库
    case authFailed           // ② 认证失败
    case needsUnlock          // ③ 需要解锁
    case pendingChanges       // ④ 有未同步更改
    case conflictCopiesCreated // ⑤ 冲突副本已创建
    case historyAgedOut       // ⑥ 历史过期（仅告知）
    case repositoryDamaged    // ⑦ 仓库损坏/不兼容

    var titleKey: String.LocalizationValue {
        switch self {
        case .cannotConnect: return "Can't reach your sync repository"
        case .authFailed: return "Sync authentication failed"
        case .needsUnlock: return "Sync vault is locked"
        case .pendingChanges: return "Some changes haven't synced yet"
        case .conflictCopiesCreated: return "Conflicting copies were created"
        case .historyAgedOut: return "Some sync history aged out"
        case .repositoryDamaged: return "Your sync repository needs attention"
        }
    }

    var detailKey: String.LocalizationValue {
        switch self {
        case .cannotConnect: return "Your notes are safe on this Mac. You can retry."
        case .authFailed: return "Your notes are safe on this Mac. Re-enter your credentials to continue syncing."
        case .needsUnlock: return "Your notes are safe on this Mac. Unlock the vault to start syncing again."
        case .pendingChanges: return "Your notes are safe on this Mac. They'll sync when you're back online."
        case .conflictCopiesCreated: return "Your notes are safe. Review the conflicting copies."
        case .historyAgedOut: return "Your notes were preserved. No action needed."
        case .repositoryDamaged: return "Your notes are safe on this Mac. Use Advanced sync settings to recover."
        }
    }

    var symbolName: String {
        switch self {
        case .cannotConnect: return "wifi.exclamationmark"
        case .authFailed: return "key.slash"
        case .needsUnlock: return "lock.fill"
        case .pendingChanges: return "arrow.triangle.2.circlepath"
        case .conflictCopiesCreated: return "exclamationmark.arrow.triangle.2.circlepath"
        case .historyAgedOut: return "clock.arrow.circlepath"
        case .repositoryDamaged: return "exclamationmark.triangle"
        }
    }
}

/// The user-facing presentation of a sync attention state.
public struct SyncStatusPresentation: Sendable, Equatable {
    public let category: SyncStatusCategory
    public let title: String
    public let detail: String
    public let action: SyncStatusAction?
    public let isDismissible: Bool
    public let symbolName: String

    public init(
        category: SyncStatusCategory,
        title: String,
        detail: String,
        action: SyncStatusAction?,
        isDismissible: Bool,
        symbolName: String
    ) {
        self.category = category
        self.title = title
        self.detail = detail
        self.action = action
        self.isDismissible = isDismissible
        self.symbolName = symbolName
    }
}

/// The action a banner presents (FR-012 action column).
public enum SyncStatusAction: Sendable, Equatable {
    case retry
    case unlock
    case reauthenticate
    case viewConflicts
    case advancedRecovery
    case none
}

// MARK: - Deterministic mapping (FR-012)

/// The sanitized input surface the mapping consumes.
public struct SyncStatusInput: Sendable, Equatable {
    public var isConfigured: Bool
    public var lastError: ProviderError?
    public var vaultLocked: Bool
    public var hasOfflineChangesPending: Bool

    public init(
        isConfigured: Bool = true,
        lastError: ProviderError? = nil,
        vaultLocked: Bool = false,
        hasOfflineChangesPending: Bool = false
    ) {
        self.isConfigured = isConfigured
        self.lastError = lastError
        self.vaultLocked = vaultLocked
        self.hasOfflineChangesPending = hasOfflineChangesPending
    }
}

public enum SyncStatusResolver {

    /// The deterministic pure-function mapping (FR-012): sync state +
    /// summary flags → the highest-priority category, or nil for zero
    /// footprint (FR-007).
    public static func resolve(
        isConfigured: Bool,
        lastError: ProviderError?,
        vaultLocked: Bool,
        hasOfflineChangesPending: Bool,
        summary: SyncSummary
    ) -> SyncStatusPresentation? {
        // No configuration → no sync UI at all (FR-007 zero footprint;
        // "not configured" lives in Settings only).
        guard isConfigured else { return nil }

        // ⑦ repository damaged/unsupported — highest priority.
        if let error = lastError, Self.isRepositoryDamage(error) {
            return presentation(for: .repositoryDamaged, action: .advancedRecovery, isDismissible: false)
        }
        // ③ needs unlock.
        if vaultLocked {
            return presentation(for: .needsUnlock, action: .unlock)
        }
        // ② auth failed.
        if let error = lastError, error == .auth || error == .forbidden {
            return presentation(for: .authFailed, action: .reauthenticate)
        }
        // ① cannot connect (transient).
        if let error = lastError, error.isTransient {
            return presentation(for: .cannotConnect, action: .retry)
        }
        // ⑤ conflict copies created.
        if summary.conflictCopiesCreated > 0 {
            return presentation(for: .conflictCopiesCreated, action: .viewConflicts)
        }
        // ④ pending changes.
        if hasOfflineChangesPending {
            return presentation(for: .pendingChanges, action: nil)
        }
        // ⑥ history aged out (informational only).
        if summary.historyAgedOutDetected {
            return presentation(for: .historyAgedOut, action: nil)
        }
        return nil
    }

    /// Resolves from the coordinator's sanitized code string (the
    /// coordinator exposes `lastErrorCode: String?`, FR-165) + summary
    /// flags. Same deterministic mapping as the ProviderError overload.
    public static func resolve(
        isConfigured: Bool,
        lastErrorCode: String?,
        vaultLocked: Bool,
        hasOfflineChangesPending: Bool,
        summary: SyncSummary
    ) -> SyncStatusPresentation? {
        resolve(
            isConfigured: isConfigured,
            lastError: lastErrorCode.flatMap(Self.error(fromCode:)),
            vaultLocked: vaultLocked,
            hasOfflineChangesPending: hasOfflineChangesPending,
            summary: summary
        )
    }

    /// Maps a sanitized code back to the ProviderError category (only the
    /// codes the mapping branches on are reconstructed; the rest are nil).
    private static func error(fromCode code: String) -> ProviderError? {
        switch code {
        case "sync.provider.auth": return .auth
        case "sync.provider.forbidden": return .forbidden
        case "sync.provider.network": return .network
        case "sync.provider.server": return .server
        case "sync.provider.conflict": return .conflict
        case "sync.provider.clockSkew": return .clockSkew
        case "sync.provider.corrupt": return .corrupt
        case "sync.provider.schemaUnsupported": return .schemaUnsupported
        case "sync.provider.wrongVault": return .wrongVault
        case "sync.provider.tls": return .tls
        default: return nil
        }
    }

    private static func isRepositoryDamage(_ error: ProviderError) -> Bool {
        switch error {
        case .corrupt, .schemaUnsupported, .wrongVault, .tls:
            return true
        default:
            return false
        }
    }

    private static func presentation(
        for category: SyncStatusCategory,
        action: SyncStatusAction?,
        isDismissible: Bool = true
    ) -> SyncStatusPresentation {
        SyncStatusPresentation(
            category: category,
            title: String(localized: category.titleKey),
            detail: String(localized: category.detailKey),
            action: action,
            isDismissible: isDismissible,
            symbolName: category.symbolName
        )
    }
}

// MARK: - Banner state machine (003 T056, FR-010/CHK005)

/// The banner's present/dismiss/re-present state (FR-010): dismiss hides;
/// no reappearance while the state is unchanged; a NEW category re-presents;
/// retry is non-blocking; retry-fails-again persists. Asserted by T052.
@MainActor
@Observable
public final class SyncBannerStateModel {
    /// The currently presented banner (nil = zero footprint).
    public private(set) var current: SyncBannerPresentation?
    /// The category last dismissed by the user (suppressed while unchanged).
    private var dismissedCategory: SyncStatusCategory?
    /// Non-blocking retry hook (FR-010a — manual-sync equivalent).
    public var onRetry: () -> Void = {}

    public init() {}

    /// Presents a category unless it equals the dismissed one (FR-010).
    public func present(category: SyncStatusCategory) {
        guard category != dismissedCategory else { return }
        current = presentation(from: category)
    }

    /// Force re-presentation (CHK005: retry-fails-again — the same
    /// category returns after a retry attempt).
    public func present(category: SyncStatusCategory, forceRePresent: Bool) {
        if forceRePresent {
            dismissedCategory = nil
            present(category: category)
        } else {
            present(category: category)
        }
    }

    /// Dismisses the banner (FR-010).
    public func dismiss() {
        if let category = current?.category {
            dismissedCategory = category
        }
        current = nil
    }

    /// Clears everything (success paths, CHK030).
    public func clearAll() {
        dismissedCategory = nil
        current = nil
    }

    /// Retries (non-blocking — FR-010a).
    public func retry() {
        onRetry()
    }

    private func presentation(from category: SyncStatusCategory) -> SyncBannerPresentation {
        SyncBannerPresentation(
            category: category,
            title: String(localized: category.titleKey),
            localDataSafe: String(localized: category.detailKey),
            actionTitle: Self.actionTitle(for: category),
            isDismissible: category != .repositoryDamaged,
            symbolName: category.symbolName
        )
    }

    private static func actionTitle(for category: SyncStatusCategory) -> String? {
        switch category {
        case .cannotConnect: return String(localized: "Retry")
        case .authFailed: return String(localized: "Re-authenticate")
        case .needsUnlock: return String(localized: "Unlock")
        case .conflictCopiesCreated: return String(localized: "Review")
        case .repositoryDamaged: return String(localized: "Advanced…")
        case .pendingChanges, .historyAgedOut: return nil
        }
    }
}

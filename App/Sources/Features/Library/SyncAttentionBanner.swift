import SwiftUI

// MARK: - SyncAttentionBanner (003 T026 — seven-category mapping complete)
//
// Per tasks.md T026: an attention-state banner placed above the grid with
// the three-element layout (what happened / local data safe / action),
// dismissible. The seven-category mapping is complete
// (SyncStatusPresentation, R3.8 remediation roadmap 2026-08-14: this
// header previously claimed the full mapping "lands in US5").
// Iconography uses SF Symbols (FR-064).
//
// Normal sync state = zero footprint (FR-007): when `presentation == nil`
// the banner renders nothing.

/// The banner's three-element presentation (what happened / local data
/// safe / action). Maps the seven sync categories (SyncStatusPresentation).
public struct SyncBannerPresentation: Sendable, Equatable {
    /// The FR-012 category (drives dismiss-suppression, FR-010).
    public let category: SyncStatusCategory?
    /// What happened (human-readable, no internal identifiers — FR-012).
    public let title: String
    /// The "your notes are safe locally" reassurance.
    public let localDataSafe: String
    /// The action title (retry/unlock/…), or nil for dismissible-only.
    public let actionTitle: String?
    /// Whether the banner can be dismissed (FR-010).
    public let isDismissible: Bool
    /// SF Symbol name (FR-064).
    public let symbolName: String

    public init(
        category: SyncStatusCategory? = nil,
        title: String,
        localDataSafe: String,
        actionTitle: String? = nil,
        isDismissible: Bool = true,
        symbolName: String = "exclamationmark.triangle"
    ) {
        self.category = category
        self.title = title
        self.localDataSafe = localDataSafe
        self.actionTitle = actionTitle
        self.isDismissible = isDismissible
        self.symbolName = symbolName
    }
}

public struct SyncAttentionBanner: View {
    let presentation: SyncBannerPresentation?
    let dismiss: () -> Void
    let action: () -> Void

    public init(
        presentation: SyncBannerPresentation?,
        dismiss: @escaping () -> Void = {},
        action: @escaping () -> Void = {}
    ) {
        self.presentation = presentation
        self.dismiss = dismiss
        self.action = action
    }

    public var body: some View {
        if let presentation {
            HStack(spacing: AppMetrics.rowSpacing) {
                Image(systemName: presentation.symbolName)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.system(size: AppMetrics.bannerTextSize, weight: .semibold))
                    Text(presentation.localDataSafe)
                        .font(.system(size: AppMetrics.bannerTextSize - 1))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let actionTitle = presentation.actionTitle {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                }
                if presentation.isDismissible {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss sync notice")
                }
            }
            .padding(AppMetrics.contentInset)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: AppMetrics.surfaceRadius))
            .padding(.horizontal, AppMetrics.contentInset)
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Sync notice: \(presentation.title). \(presentation.localDataSafe)")
        }
    }
}

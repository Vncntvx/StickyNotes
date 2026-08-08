import SwiftUI

// MARK: - SyncAttentionBanner (003 T026 shell → US5 complete)
//
// Per tasks.md T026: a basic attention-state banner placed above the grid
// with the three-element layout (what happened / local data safe / action),
// dismissible. The FULL seven-category mapping lands in US5 (T052/T056,
// FR-010); this shell wires the presentation model + dismiss skeleton so
// the layout exists. Iconography uses SF Symbols (FR-064).
//
// Normal sync state = zero footprint (FR-007): when `presentation == nil`
// the banner renders nothing.

/// The banner's three-element presentation (what happened / local data
/// safe / action). Fleshed out per seven categories in US5 (T055).
public struct SyncBannerPresentation: Sendable, Equatable {
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
        title: String,
        localDataSafe: String,
        actionTitle: String? = nil,
        isDismissible: Bool = true,
        symbolName: String = "exclamationmark.triangle"
    ) {
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

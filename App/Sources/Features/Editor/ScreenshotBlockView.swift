import SwiftUI
import Domain

// MARK: - ScreenshotBlockView + EmbeddedImageBlockView (T168/T292, US7)
//
// Per tasks.md T292 and spec FR-090/FR-090a/FR-091/FR-092/FR-093/FR-094/
// FR-094a/FR-094b/FR-095: screenshot association metadata + cover
// selection (at most one cover per note, persisted through the host —
// Note.coverScreenshotBlockId, FR-094b), caption editing, and the FR-095a
// viewer entry. Embedded clipboard image with view/copy/drag-out/save/
// remove actions (FR-090). Media renders from the 256px thumbnail
// (FR-094a) — never decoded at full resolution in the grid (SC-008).

/// Embedded-image block actions (T292, FR-090).
public enum EmbeddedImageAction: Sendable {
    case view
    case copy
    case saveAs
    case remove
}

/// A screenshot block: thumbnail frame + caption + cover selection.
public struct ScreenshotBlockView: View {
    let block: Block
    let onSetCover: (Bool) -> Void
    let onUpdateCaption: (String?) -> Void
    let onViewLarger: () -> Void

    @State private var caption: String?
    @State private var isCover = false

    public init(
        block: Block,
        onSetCover: @escaping (Bool) -> Void = { _ in },
        onUpdateCaption: @escaping (String?) -> Void = { _ in },
        onViewLarger: @escaping () -> Void = {}
    ) {
        self.block = block
        self.onSetCover = onSetCover
        self.onUpdateCaption = onUpdateCaption
        self.onViewLarger = onViewLarger
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onViewLarger) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.4))
                    .frame(height: 120)
                    .overlay {
                        Image(systemName: "camera")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isCover {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .padding(6)
                                .accessibilityLabel("Card cover screenshot")
                        }
                    }
            }
            .buttonStyle(.plain)
            .help("View larger (FR-095)")

            // FR-093: caption editing persists through the host.
            TextField("Caption", text: Binding(
                get: { caption ?? "" },
                set: { newValue in
                    caption = newValue
                    onUpdateCaption(newValue.isEmpty ? nil : newValue)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)

            HStack {
                // FR-094: cover selection (at most one per note — enforced
                // transactionally by the host).
                Button(isCover ? "Remove Cover" : "Set as Cover") {
                    let newValue = !isCover
                    isCover = newValue
                    onSetCover(newValue)
                }
                .controlSize(.small)
                .accessibilityLabel(isCover ? "Remove as card cover" : "Set as card cover")
                Spacer()
            }
        }
        .task {
            if case .screenshot(let payload) = block.payload {
                caption = payload.caption
                isCover = payload.isCover
            }
        }
    }
}

/// An embedded clipboard image block (FR-090): view/copy/drag-out/save/
/// remove.
public struct EmbeddedImageBlockView: View {
    let block: Block
    let onAction: (EmbeddedImageAction) -> Void

    @State private var caption: String?

    public init(block: Block, onAction: @escaping (EmbeddedImageAction) -> Void = { _ in }) {
        self.block = block
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.4))
                .frame(height: 120)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("View") { onAction(.view) }
                    .controlSize(.small)
                Button("Copy") { onAction(.copy) }
                    .controlSize(.small)
                Button("Save As…") { onAction(.saveAs) }
                    .controlSize(.small)
                Button("Remove", role: .destructive) { onAction(.remove) }
                    .controlSize(.small)
                Spacer()
            }
        }
        .task {
            if case .image(let payload) = block.payload {
                caption = payload.caption
            }
        }
    }
}

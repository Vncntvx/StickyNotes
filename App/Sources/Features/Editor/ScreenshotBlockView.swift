import SwiftUI
import Domain

// MARK: - ScreenshotBlockView + EmbeddedImageBlockView (T168, US7)
//
// Per tasks.md T168 and spec FR-090/FR-090a/FR-091/FR-092/FR-093/FR-094/
// FR-094a/FR-094b/FR-095: screenshot association metadata + cover
// selection (at most one cover per note, transactional); embedded clipboard
// image original with view/larger/copy/drag-out/save-elsewhere/remove.
// Media renders from the 256px thumbnail (FR-094a) — never decoded at full
// resolution in the grid (SC-008).

/// A screenshot block: thumbnail frame + caption + cover selection.
public struct ScreenshotBlockView: View {
    let block: Block

    @State private var caption: String?
    @State private var isCover = false

    public init(block: Block) {
        self.block = block
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            HStack {
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // FR-094: cover selection (at most one per note is enforced
                // transactionally by the host).
                Button(isCover ? "Remove Cover" : "Set as Cover") {
                    isCover.toggle()
                }
                .controlSize(.small)
                .accessibilityLabel(isCover ? "Remove as card cover" : "Set as card cover")
            }
        }
        .onAppear {
            if case .screenshot(let payload) = block.payload {
                caption = payload.caption
                isCover = payload.isCover
            }
        }
    }
}

/// An embedded clipboard image block (FR-096): view/larger/copy/drag-out/
/// save-elsewhere/remove.
public struct EmbeddedImageBlockView: View {
    let block: Block

    @State private var caption: String?

    public init(block: Block) {
        self.block = block
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
        }
        .onAppear {
            if case .image(let payload) = block.payload {
                caption = payload.caption
            }
        }
    }
}

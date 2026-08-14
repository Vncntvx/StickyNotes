import SwiftUI
import AppKit
import Domain

// MARK: - ScreenshotViewer (T168/T258/T297, FR-095/FR-095a)
//
// Per tasks.md T168/T258/T297 and spec FR-095a (clarified 2026-08-07): the
// screenshot viewer opens in an independent, borderless, note-style window
// (several viewers MAY coexist; images drag out). Zoom is bounded 25%–400%
// in 25% steps (scroll/pinch + ⌘+/⌘- equivalents); double-click toggles
// actual size (100%) ↔ fit-to-window; arrow keys navigate between the same
// note's screenshots; Return (or double-click on a screenshot) enters
// caption editing. The viewer never activates the captured application
// (FR-095).
//
// T297 (Phase 28): the viewer loads the REAL image through the injected
// `imageProvider` — the FR-094a 256px thumbnail below 100% zoom, the
// original at ≥100% zoom (never full-res decoded for grid surfaces). The
// FR-095 action set is complete: Copy (pasteboard PNG), Drag-out
// (copy-only, FR-102 semantics), Save As (NSSavePanel), and Delete
// Association (removes the block; FR-094b cover nullification is handled by
// the persistence layer's FK ON DELETE SET NULL).

/// The bounded zoom step set (FR-095a: 25%–400% in 25% steps).
public enum ScreenshotZoom {
    public static let steps: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0]

    public static func clamp(_ zoom: Double) -> Double {
        min(max(zoom, 0.25), 4.0)
    }

    /// Next discrete step (24% clamps to 25%).
    public static func nextStep(after zoom: Double) -> Double {
        clamp(steps.first(where: { $0 > zoom + 0.001 }) ?? 4.0)
    }

    public static func previousStep(before zoom: Double) -> Double {
        clamp(steps.last(where: { $0 < zoom - 0.001 }) ?? 0.25)
    }
}

/// The viewer content (hosted in an independent borderless note-style
/// window by the App).
public struct ScreenshotViewer: View {
    let noteId: UUID
    let screenshots: [ScreenshotPayload]
    let openScreenshot: (Int) -> Void
    /// T297: resolves asset bytes (thumbnail/original) by asset id. The App
    /// wires the composed AssetStore.
    let imageProvider: (UUID) async throws -> Data?
    /// T297: deletes the screenshot block that owns the given original asset
    /// id (FR-094b cover nullification at the persistence layer).
    let onDeleteAssociation: (UUID) -> Void

    @State private var zoom: Double = 1.0
    @State private var currentIndex = 0
    @State private var isEditingCaption = false
    @State private var image: NSImage?

    public init(
        noteId: UUID,
        screenshots: [ScreenshotPayload],
        openScreenshot: @escaping (Int) -> Void = { _ in },
        imageProvider: @escaping (UUID) async throws -> Data? = { _ in nil },
        onDeleteAssociation: @escaping (UUID) -> Void = { _ in }
    ) {
        self.noteId = noteId
        self.screenshots = screenshots
        self.openScreenshot = openScreenshot
        self.imageProvider = imageProvider
        self.onDeleteAssociation = onDeleteAssociation
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Screenshot \(currentIndex + 1) of \(screenshots.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // T297 FR-095 action set.
                Button {
                    copyCurrentImage()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")
                .accessibilityLabel("Copy screenshot")

                Button {
                    saveCurrentImageAs()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save As…")
                .accessibilityLabel("Save screenshot as")

                Button(role: .destructive) {
                    if let payload = currentPayload {
                        onDeleteAssociation(payload.originalAssetId)
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete Association")
                .accessibilityLabel("Delete screenshot association")

                Divider().frame(height: 14)

                // ⌘+ / ⌘- equivalents (FR-095a).
                Button { zoom = ScreenshotZoom.previousStep(before: zoom) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .keyboardShortcut("-", modifiers: .command)
                .help("Zoom out")
                .accessibilityLabel("Zoom out")

                Button { zoom = ScreenshotZoom.nextStep(after: zoom) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .keyboardShortcut("+", modifiers: .command)
                .help("Zoom in")
                .accessibilityLabel("Zoom in")

                Text("\(Int(zoom * 100))%")
                    .font(.caption)
                    .monospacedDigit()
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.4))
                    .overlay {
                        if let image {
                            // T297: real screenshot — FR-094a thumbnail below
                            // 100% zoom, original at ≥100%.
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onDrag {
                                    NSItemProvider(object: image)   // copy-only drag-out (FR-102)
                                }
                        } else {
                            Image(systemName: "camera")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(zoom)   // bounded 25–400%
            .onTapGesture(count: 2) {
                // Double-click toggles actual size ↔ fit-to-window.
                zoom = zoom == 1.0 ? 0.5 : 1.0
            }
            .focusable()
            .onKeyPress(.rightArrow) {
                navigate(to: currentIndex + 1)
                return .handled
            }
            .onKeyPress(.leftArrow) {
                navigate(to: currentIndex - 1)
                return .handled
            }
            .onKeyPress(.return) {
                isEditingCaption = true
                return .handled
            }
            .gesture(
                MagnifyGesture()
                    .onEnded { value in
                        if value.magnification > 1 {
                            zoom = ScreenshotZoom.nextStep(after: zoom)
                        } else if value.magnification < 1 {
                            zoom = ScreenshotZoom.previousStep(before: zoom)
                        }
                    }
            )
        }
        .padding(12)
        .task(id: ViewerLoadKey(index: currentIndex, usesThumbnail: zoom < 1.0)) {
            await loadCurrentImage()
        }
    }

    private var currentPayload: ScreenshotPayload? {
        screenshots.indices.contains(currentIndex) ? screenshots[currentIndex] : nil
    }

    private func navigate(to index: Int) {
        guard !screenshots.isEmpty else { return }
        currentIndex = min(max(index, 0), screenshots.count - 1)
        openScreenshot(currentIndex)
    }

    // MARK: - Image loading (T297, FR-094a)

    private func loadCurrentImage() async {
        guard let payload = currentPayload else {
            image = nil
            return
        }
        // FR-094a: the 256px thumbnail participates below 100% zoom; the
        // original at ≥100%. Never decode the original for grid surfaces.
        // R1.3 (remediation-phase1 T014): the thumbnail may be absent
        // (generation failed, SC-008 — never fall back to the original as
        // the thumbnail). In the explicit viewer a missing thumbnail falls
        // back to the original (the viewer is a full-resolution surface,
        // not the card grid).
        let assetId: UUID
        if zoom < 1.0, let thumbnail = payload.thumbnailAssetId {
            assetId = thumbnail
        } else {
            assetId = payload.originalAssetId
        }
        guard let data = try? await imageProvider(assetId) else {
            image = nil
            return
        }
        image = NSImage(data: data)
    }

    // MARK: - FR-095 actions (T297)

    private func copyCurrentImage() {
        guard let payload = currentPayload else { return }
        Task {
            guard let data = try? await imageProvider(payload.originalAssetId) else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
        }
    }

    private func saveCurrentImageAs() {
        guard let payload = currentPayload else { return }
        Task {
            guard let data = try? await imageProvider(payload.originalAssetId) else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "screenshot.png"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Identifies the viewer's current load: (index, thumbnail-or-original).
private struct ViewerLoadKey: Equatable {
    let index: Int
    let usesThumbnail: Bool
}

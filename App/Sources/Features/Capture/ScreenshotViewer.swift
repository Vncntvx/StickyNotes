import SwiftUI
import Domain

// MARK: - ScreenshotViewer (T168/T258, FR-095a)
//
// Per tasks.md T168/T258 and spec FR-095a (clarified 2026-08-07): the
// screenshot viewer opens in an independent, borderless, note-style window
// (several viewers MAY coexist; images drag out). Zoom is bounded 25%–400%
// in 25% steps (scroll/pinch + ⌘+/⌘- equivalents); double-click toggles
// actual size (100%) ↔ fit-to-window; arrow keys navigate between the same
// note's screenshots; Return (or double-click on a screenshot) enters
// caption editing. The viewer never activates the captured application
// (FR-095).

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

    @State private var zoom: Double = 1.0
    @State private var currentIndex = 0
    @State private var isEditingCaption = false

    public init(noteId: UUID, screenshots: [ScreenshotPayload], openScreenshot: @escaping (Int) -> Void = { _ in }) {
        self.noteId = noteId
        self.screenshots = screenshots
        self.openScreenshot = openScreenshot
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Screenshot \(currentIndex + 1) of \(screenshots.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

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
                        Image(systemName: "camera")
                            .font(.title)
                            .foregroundStyle(.secondary)
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
    }

    private func navigate(to index: Int) {
        guard !screenshots.isEmpty else { return }
        currentIndex = min(max(index, 0), screenshots.count - 1)
        openScreenshot(currentIndex)
    }
}

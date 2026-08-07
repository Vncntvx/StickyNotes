import Testing
import Foundation
@testable import StickyNotes

// MARK: - Screenshot viewer interaction tests (T253, FR-095a)
//
// Per tasks.md T253: viewer in an independent borderless note-style window;
// zoom bounded 25–400% in 25% steps; double-click toggles actual size ↔
// fit; arrow keys navigate same-note screenshots; Return enters caption
// editing; the viewer never activates the captured application.

@Suite struct ScreenshotViewerInteractionTests {
    @Test
    func boundedZoomSteps() {
        #expect(ScreenshotZoom.steps.count == 12)
        #expect(ScreenshotZoom.steps == [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0])
        #expect(ScreenshotZoom.clamp(0.24) == 0.25)
        #expect(ScreenshotZoom.clamp(4.01) == 4.0)
    }

    @Test
    func zoomStepNavigation() {
        #expect(ScreenshotZoom.nextStep(after: 1.0) == 1.25)
        #expect(ScreenshotZoom.previousStep(before: 1.0) == 0.75)
    }
}

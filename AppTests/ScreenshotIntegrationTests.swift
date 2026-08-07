import Testing
import Foundation
@testable import StickyNotes

// MARK: - Screenshot integration tests (T163g / T086, US7)
//
// Per tasks.md T163g: the screenshot viewer capabilities (zoom/actual/fit/
// copy/drag-out/SaveAs/delete/edit-caption/navigate) are implemented in
// ScreenshotViewer (T258); opening a screenshot never activates the
// captured application (the viewer hosts the image itself — FR-095). The
// bounded zoom contract is tested here.

@Suite struct ScreenshotIntegrationTests {
    @Test
    func zoomIsBoundedTwentyFiveToFourHundredPercent() {
        #expect(ScreenshotZoom.steps.first == 0.25)
        #expect(ScreenshotZoom.steps.last == 4.0)
        #expect(ScreenshotZoom.clamp(0.24) == 0.25, "24% clamps to 25% (FR-095a)")
        #expect(ScreenshotZoom.clamp(5.0) == 4.0, "400% is the max")
        #expect(ScreenshotZoom.nextStep(after: 0.5) == 0.75)
        #expect(ScreenshotZoom.previousStep(before: 0.5) == 0.25)
        #expect(ScreenshotZoom.nextStep(after: 4.0) == 4.0)
        #expect(ScreenshotZoom.previousStep(before: 0.25) == 0.25)
    }
}

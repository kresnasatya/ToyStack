import CoreGraphics
import Testing

@testable import Engine

@Suite
struct ContentPresentationStateTests {

    @Test func firstFrameBindsAtViewSize() {
        var state = ContentPresentationState()
        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 100, height: 50)
        )

        #expect(decision == .bind)
        #expect(state.baseViewSize == CGSize(width: 100, height: 50))
    }

    @Test func sizeChangePreviewsFromBaseViewSize() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 100, height: 50)
        )

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 1, sequence: 2),
            viewSize: CGSize(width: 120, height: 50)
        )

        #expect(decision == .preview(from: CGSize(width: 100, height: 50)))
        #expect(state.baseViewSize == CGSize(width: 100, height: 50))
    }

    @Test func repeatedPreviewsUseTheBaseViewSize() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 100, height: 50)
        )
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 2),
            viewSize: CGSize(width: 120, height: 50)
        )

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 1, sequence: 3),
            viewSize: CGSize(width: 140, height: 50)
        )

        #expect(decision == .preview(from: CGSize(width: 100, height: 50)))
        #expect(state.baseViewSize == CGSize(width: 100, height: 50))
    }

    @Test func sameSizeAfterPreviewStillPreviews() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 100, height: 50)
        )
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 2),
            viewSize: CGSize(width: 120, height: 50)
        )

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 1, sequence: 3),
            viewSize: CGSize(width: 120, height: 50)
        )

        #expect(decision == .preview(from: CGSize(width: 100, height: 50)))
    }

    @Test func sameSizeAtBaseBinds() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 100, height: 50)
        )

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 1, sequence: 2),
            viewSize: CGSize(width: 100, height: 50)
        )

        #expect(decision == .bind)
    }

    @Test func newContentRevisionBindsAtCurrentSize() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 100, height: 50)
        )
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 2),
            viewSize: CGSize(width: 120, height: 50)
        )

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 3),
            viewSize: CGSize(width: 120, height: 50)
        )

        #expect(decision == .bind)
        #expect(state.baseViewSize == CGSize(width: 120, height: 50))
    }

    @Test func newRevisionPreviewsUntilLayoutMatchesViewport() {
        var state = ContentPresentationState()
        let first: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 100, height: 50),
            layoutSize: CGSize(width: 100, height: 50),
            stagingLayers: false
        )
        #expect(first == .bind)

        let whileResizing: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 2),
            viewSize: CGSize(width: 120, height: 50),
            layoutSize: CGSize(width: 100, height: 50),
            stagingLayers: false
        )
        #expect(whileResizing == .preview(from: CGSize(width: 100, height: 50)))

        let finished: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 3),
            viewSize: CGSize(width: 120, height: 50),
            layoutSize: CGSize(width: 120, height: 50),
            stagingLayers: false
        )
        #expect(finished == .bind)
    }

    @Test func staleLayoutPreviewsFromShownWidth() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 1440, height: 703),
            layoutSize: CGSize(width: 1440, height: 703),
            stagingLayers: false
        )
        state.didShow(
            layoutSize: CGSize(width: 1440, height: 703),
            viewSize: CGSize(width: 1440, height: 703)
        )

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 2),
            viewSize: CGSize(width: 1201, height: 703),
            layoutSize: CGSize(width: 1220, height: 703),
            stagingLayers: false
        )

        #expect(decision == .preview(from: CGSize(width: 1440, height: 703)))
    }

    @Test func bindNotYetShownKeepsPreviewingFromShownWidth() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 1440, height: 703),
            layoutSize: CGSize(width: 1440, height: 703),
            stagingLayers: false
        )
        state.didShow(
            layoutSize: CGSize(width: 1440, height: 703),
            viewSize: CGSize(width: 1440, height: 703)
        )
        // Its layout fits the view, but its layers are still staging behind
        // the 1440 layers on screen, so those are scaled to the new width.
        let staged: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 2),
            viewSize: CGSize(width: 1300, height: 703),
            layoutSize: CGSize(width: 1300, height: 703),
            stagingLayers: true
        )
        #expect(staged == .preview(from: CGSize(width: 1440, height: 703)))

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 3, sequence: 3),
            viewSize: CGSize(width: 1250, height: 703),
            layoutSize: CGSize(width: 1300, height: 703),
            stagingLayers: true
        )

        #expect(decision == .preview(from: CGSize(width: 1440, height: 703)))
    }

    /// Nothing will replace the layers on screen, so the fitting frame must
    /// bind; previewing would keep the old width on screen forever.
    @Test func fittingFrameBindsWhenNoLayersAreStaging() {
        var state = ContentPresentationState()
        state.didShow(
            layoutSize: CGSize(width: 1440, height: 703),
            viewSize: CGSize(width: 1440, height: 703)
        )

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 2),
            viewSize: CGSize(width: 1300, height: 703),
            layoutSize: CGSize(width: 1300, height: 703),
            stagingLayers: false
        )

        #expect(decision == .bind)
    }

    /// New layers staging at the width already on screen need no scaling.
    @Test func stagingAtTheShownWidthBinds() {
        var state = ContentPresentationState()
        state.didShow(
            layoutSize: CGSize(width: 1300, height: 703),
            viewSize: CGSize(width: 1300, height: 703)
        )

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 2),
            viewSize: CGSize(width: 1300, height: 703),
            layoutSize: CGSize(width: 1300, height: 703),
            stagingLayers: true
        )

        #expect(decision == .bind)
    }

    @Test func sameWidthDifferentHeightBinds() {
        var state = ContentPresentationState()
        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 900, height: 766),
            layoutSize: CGSize(width: 900, height: 700),
            stagingLayers: false
        )
        #expect(decision == .bind)
    }

    @Test func widthChangeIgnoresToolbarHeightDifference() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 900, height: 766),
            layoutSize: CGSize(width: 900, height: 700),
            stagingLayers: false
        )
        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 2),
            viewSize: CGSize(width: 500, height: 766),
            layoutSize: CGSize(width: 900, height: 700),
            stagingLayers: false
        )
        #expect(decision == .preview(from: CGSize(width: 900, height: 766)))
    }

    @Test func newContentRevisionAtNewSizeBindsThere() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 100, height: 50)
        )

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 2),
            viewSize: CGSize(width: 160, height: 80)
        )

        #expect(decision == .bind)
        #expect(state.baseViewSize == CGSize(width: 160, height: 80))
    }

    // MARK: - Which generations are uploaded

    /// During a drag the layout trails the window by a frame or two, so a
    /// newer layout almost never has the window's exact width. It is still
    /// closer to the window than the older layers on screen; refusing it kept
    /// one picture on screen for up to 1.2 s on a long page.
    @Test func newerLayoutAtAnotherWidthIsStaged() {
        #expect(ContentPresentationState.stages(generation: 8, shown: 7))
    }

    @Test func generationOnScreenIsNotStagedAgain() {
        #expect(!ContentPresentationState.stages(generation: 7, shown: 7))
    }

    /// With nothing on screen there is nothing to upload behind; the first
    /// frame binds directly.
    @Test func firstGenerationBindsInsteadOfStaging() {
        #expect(!ContentPresentationState.stages(generation: 1, shown: nil))
    }
}

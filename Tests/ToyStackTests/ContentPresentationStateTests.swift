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
            layoutSize: CGSize(width: 100, height: 50)
        )
        #expect(first == .bind)

        let whileResizing: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 2),
            viewSize: CGSize(width: 120, height: 50),
            layoutSize: CGSize(width: 100, height: 50)
        )
        #expect(whileResizing == .preview(from: CGSize(width: 100, height: 50)))

        let finished: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 3),
            viewSize: CGSize(width: 120, height: 50),
            layoutSize: CGSize(width: 120, height: 50)
        )
        #expect(finished == .bind)
    }

    @Test func staleLayoutPreviewsFromShownWidth() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 1440, height: 703),
            layoutSize: CGSize(width: 1440, height: 703)
        )
        state.didShow(
            layoutSize: CGSize(width: 1440, height: 703),
            viewSize: CGSize(width: 1440, height: 703)
        )

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 2),
            viewSize: CGSize(width: 1201, height: 703),
            layoutSize: CGSize(width: 1220, height: 703)
        )

        #expect(decision == .preview(from: CGSize(width: 1440, height: 703)))
    }

    @Test func bindNotYetShownKeepsPreviewingFromShownWidth() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 1440, height: 703),
            layoutSize: CGSize(width: 1440, height: 703)
        )
        state.didShow(
            layoutSize: CGSize(width: 1440, height: 703),
            viewSize: CGSize(width: 1440, height: 703)
        )
        // Bound, but its layers are still staging behind the 1440 layers.
        let staged: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 2),
            viewSize: CGSize(width: 1300, height: 703),
            layoutSize: CGSize(width: 1300, height: 703)
        )
        #expect(staged == .bind)

        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 3, sequence: 3),
            viewSize: CGSize(width: 1250, height: 703),
            layoutSize: CGSize(width: 1300, height: 703)
        )

        #expect(decision == .preview(from: CGSize(width: 1440, height: 703)))
    }

    @Test func sameWidthDifferentHeightBinds() {
        var state = ContentPresentationState()
        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 900, height: 766),
            layoutSize: CGSize(width: 900, height: 700)
        )
        #expect(decision == .bind)
    }

    @Test func widthChangeIgnoresToolbarHeightDifference() {
        var state = ContentPresentationState()
        _ = state.decide(
            revision: PresentedRevision(content: 1, sequence: 1),
            viewSize: CGSize(width: 900, height: 766),
            layoutSize: CGSize(width: 900, height: 700)
        )
        let decision: ContentPresentationState.Decision = state.decide(
            revision: PresentedRevision(content: 2, sequence: 2),
            viewSize: CGSize(width: 500, height: 766),
            layoutSize: CGSize(width: 900, height: 700)
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
}

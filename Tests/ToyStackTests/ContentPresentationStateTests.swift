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

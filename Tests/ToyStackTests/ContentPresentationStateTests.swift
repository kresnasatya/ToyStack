import CoreGraphics
import Testing

@testable import Engine

@Suite
struct ContentPresentationStateTests {

    @Test func firstFrameBindsAtViewSize() {
        var state = ContentPresentationState()
        let decision: ContentPresentationState.Decision = state.decide(
            revision: 1,
            viewSize: CGSize(width: 100, height: 50)
        )

        #expect(decision == .bind)
        #expect(state.lastViewSize == CGSize(width: 100, height: 50))
    }

    @Test func sizeChangePreviewsFromPreviousViewSize() {
        var state = ContentPresentationState()
        _ = state.decide(revision: 1, viewSize: CGSize(width: 100, height: 50))

        let decision: ContentPresentationState.Decision = state.decide(
            revision: 1,
            viewSize: CGSize(width: 120, height: 50)
        )

        #expect(decision == .preview(from: CGSize(width: 100, height: 50)))
    }

    @Test func repeatedPreviewsUseThePreviousViewSize() {
        var state = ContentPresentationState()
        _ = state.decide(revision: 1, viewSize: CGSize(width: 100, height: 50))
        _ = state.decide(revision: 1, viewSize: CGSize(width: 120, height: 50))

        let decision: ContentPresentationState.Decision = state.decide(
            revision: 1,
            viewSize: CGSize(width: 140, height: 50)
        )

        #expect(decision == .preview(from: CGSize(width: 120, height: 50)))
        #expect(state.lastViewSize == CGSize(width: 140, height: 50))
    }

    @Test func newRevisionBindsAtCurrentSize() {
        var state = ContentPresentationState()
        _ = state.decide(revision: 1, viewSize: CGSize(width: 100, height: 50))
        _ = state.decide(revision: 1, viewSize: CGSize(width: 120, height: 50))

        let decision: ContentPresentationState.Decision = state.decide(
            revision: 2,
            viewSize: CGSize(width: 120, height: 50)
        )

        #expect(decision == .bind)
        #expect(state.lastViewSize == CGSize(width: 120, height: 50))
    }

    @Test func newRevisionAtNewSizeBindsThere() {
        var state = ContentPresentationState()
        _ = state.decide(revision: 1, viewSize: CGSize(width: 100, height: 50))

        let decision: ContentPresentationState.Decision = state.decide(
            revision: 2,
            viewSize: CGSize(width: 160, height: 80)
        )

        #expect(decision == .bind)
        #expect(state.lastViewSize == CGSize(width: 160, height: 80))
    }
}

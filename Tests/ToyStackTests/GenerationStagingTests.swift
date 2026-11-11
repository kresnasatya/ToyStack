import Testing

@testable import Engine

@Suite
struct GenerationStagingTests {
    @Test func firstFrameStartsStaging() {
        var staging: GenerationStaging<String> = GenerationStaging()
        let offer: GenerationStaging<String>.Offer = staging.offer("a", generation: 1)
        #expect(offer == .started)
        #expect(staging.current?.frame == "a")
        #expect(staging.waiting == nil)
    }

    @Test func newerGenerationWaitsBehindTheOneBeingStaged() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("a", generation: 1)
        let offer: GenerationStaging<String>.Offer = staging.offer("b", generation: 2)
        #expect(offer == .queued)
        #expect(staging.current?.generation == 1)
        #expect(staging.waiting?.frame == "b")
    }

    @Test func sameGenerationRefreshesTheFrameBeingStaged() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("a", generation: 1)
        let offer: GenerationStaging<String>.Offer = staging.offer("a2", generation: 1)
        #expect(offer == .refreshed)
        #expect(staging.current?.frame == "a2")
        #expect(staging.waiting == nil)
    }

    /// Only the newest frame waits; older waiting frames would only delay it.
    @Test func finishingStartsOnlyTheNewestWaitingFrame() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("a", generation: 1)
        _ = staging.offer("b", generation: 2)
        _ = staging.offer("c", generation: 3)

        let next: String? = staging.finish()

        #expect(next == "c")
        #expect(staging.current?.generation == 3)
        #expect(staging.waiting == nil)
        #expect(staging.finish() == nil)
        #expect(staging.current == nil)
    }

    @Test func currentGenerationRefreshesWhileAFrameWaits() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("a", generation: 1)
        _ = staging.offer("b", generation: 2)
        _ = staging.offer("a2", generation: 1)

        #expect(staging.current?.frame == "a2")
        #expect(staging.waiting?.frame == "b")
        #expect(staging.finish() == "b")
    }

    @Test func cancelDropsCurrentAndWaiting() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("a", generation: 1)
        _ = staging.offer("b", generation: 2)

        staging.cancel()

        #expect(staging.current == nil)
        #expect(staging.waiting == nil)
        #expect(staging.offer("c", generation: 3) == .started)
    }

    // MARK: - Skipping a stale upload once the resize settles

    /// The window stopped at the waiting frame's width; the frame being
    /// uploaded was laid out for a width the window no longer has, so
    /// finishing it would only delay the final image.
    @Test func settledResizeSkipsToTheWaitingFrame() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("stale", generation: 1)
        _ = staging.offer("final", generation: 2)

        let skipped: Bool = staging.skipStale(
            settled: true,
            currentFinishesNow: { _ in false },
            fits: { $0 == "final" }
        )

        #expect(skipped)
        #expect(staging.current?.frame == "final")
        #expect(staging.waiting == nil)
    }

    @Test func movingResizeKeepsTheStartedUpload() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("stale", generation: 1)
        _ = staging.offer("final", generation: 2)

        var asked: Bool = false
        let skipped: Bool = staging.skipStale(
            settled: false,
            currentFinishesNow: { _ in asked = true; return false },
            fits: { $0 == "final" }
        )

        #expect(!skipped)
        // Counting the tiles left walks every placement; a moving drag must
        // not pay for it on each present.
        #expect(!asked)
        #expect(staging.current?.frame == "stale")
        #expect(staging.waiting?.frame == "final")
    }

    /// New generations at an unchanged width (an animation) must not keep
    /// replacing each other, or none would ever reach the screen.
    @Test func uploadThatFitsTheViewIsNeverSkipped() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("a", generation: 1)
        _ = staging.offer("b", generation: 2)

        let skipped: Bool = staging.skipStale(
            settled: true,
            currentFinishesNow: { _ in false },
            fits: { _ in true }
        )

        #expect(!skipped)
        #expect(staging.current?.frame == "a")
    }

    /// The window moved away from the waiting frame's width too; skipping to
    /// it would only trade one stale upload for another.
    @Test func waitingFrameThatNoLongerFitsIsNotSkippedTo() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("a", generation: 1)
        _ = staging.offer("b", generation: 2)

        let skipped: Bool = staging.skipStale(
            settled: true,
            currentFinishesNow: { _ in false },
            fits: { _ in false }
        )

        #expect(!skipped)
        #expect(staging.current?.frame == "a")
    }

    @Test func nothingWaitingMeansNothingToSkipTo() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("stale", generation: 1)

        let skipped: Bool = staging.skipStale(
            settled: true,
            currentFinishesNow: { _ in false },
            fits: { _ in false }
        )

        #expect(!skipped)
        #expect(staging.current?.frame == "stale")
    }

    /// The stale upload has so few tiles left that this present finishes it.
    /// Dropping it would keep an older, narrower image on screen until the
    /// final frame is uploaded from scratch; finishing it shows a closer image
    /// now and starts the final frame on the next present.
    @Test func uploadThatFinishesThisPresentIsNotSkipped() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("stale", generation: 1)
        _ = staging.offer("final", generation: 2)

        let skipped: Bool = staging.skipStale(
            settled: true,
            currentFinishesNow: { $0 == "stale" },
            fits: { $0 == "final" }
        )

        #expect(!skipped)
        #expect(staging.current?.frame == "stale")
        #expect(staging.waiting?.frame == "final")
    }
}

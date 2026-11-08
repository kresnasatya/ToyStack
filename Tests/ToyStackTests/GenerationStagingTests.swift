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

    /// A started upload is never thrown away for a newer layout: the newer
    /// frame waits until the current generation is on screen.
    @Test func newerGenerationWaitsBehindTheOneBeingStaged() {
        var staging: GenerationStaging<String> = GenerationStaging()
        _ = staging.offer("a", generation: 1)
        let offer: GenerationStaging<String>.Offer = staging.offer("b", generation: 2)
        #expect(offer == .queued)
        #expect(staging.current?.generation == 1)
        #expect(staging.waiting?.frame == "b")
    }

    /// The same generation can arrive again with a new scroll offset; the
    /// upload continues with the newer frame instead of starting over.
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

    /// A repeat of the generation being uploaded updates that upload, even
    /// while a newer frame is waiting behind it.
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
}

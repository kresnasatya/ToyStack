/// Paint output, composited updates, the last painted region, and paint's reusable output.
struct FrameDisplayState: Sendable {
    var paint: FramePaintState
    var composite: FrameCompositeState
    var painted: FramePaintedState
    var caches: PaintCacheStore

    init() {
        self.paint = FramePaintState()
        self.composite = FrameCompositeState()
        self.painted = FramePaintedState()
        self.caches = PaintCacheStore()
    }
}

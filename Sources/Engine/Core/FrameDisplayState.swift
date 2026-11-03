/// Paint output, composited updates, and the last painted region.
struct FrameDisplayState {
    var paint: FramePaintState
    var composite: FrameCompositeState
    var painted: FramePaintedState

    init() {
        self.paint = FramePaintState()
        self.composite = FrameCompositeState()
        self.painted = FramePaintedState()
    }
}

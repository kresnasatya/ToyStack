/// Work that must reach the next animation frame.
struct FrameScheduleState {
    var needsRender: Bool

    #if DEBUG
    var debugDumpDependencies: Bool
    #endif

    init() {
        self.needsRender = false
        #if DEBUG
        self.debugDumpDependencies = false
        #endif
    }
}

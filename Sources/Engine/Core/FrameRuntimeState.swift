struct FrameRuntimeState {
    var script: JSRuntime!
    var schedule: FrameScheduleState
    var interaction: FrameInteractionState
    var animation: FrameAnimationState

    init() {
        self.script = nil
        self.schedule = FrameScheduleState()
        self.interaction = FrameInteractionState()
        self.animation = FrameAnimationState()
    }
}

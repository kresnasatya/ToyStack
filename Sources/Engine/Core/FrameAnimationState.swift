/// Running animation count and the current scroll tween.
struct FrameAnimationState {
    var activeCount: Int
    var tween: ScrollTween?

    init() {
        self.activeCount = 0
        self.tween = nil
    }
}

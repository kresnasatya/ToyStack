protocol Animation: AnyObject {
    func animate() -> String?
}

struct TransitionSpec {
    let numFrames: Int
    let easing: EasingFunction
}

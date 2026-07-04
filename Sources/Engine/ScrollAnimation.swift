import CoreGraphics

class ScrollAnimation {
    let target: CGFloat

    private let start: CGFloat
    private let numFrames: Int
    private let easing: EasingFunction
    private var frameCount: Int = 0

    init(
        from start: CGFloat, to target: CGFloat, numFrames: Int = 12,
        easing: EasingFunction = .easeOut
    ) {
        self.start = start
        self.target = target
        self.numFrames = numFrames
        self.easing = easing
    }

    func animate() -> CGFloat? {
        frameCount += 1
        if frameCount > numFrames { return nil }
        let t = Double(frameCount) / Double(numFrames)
        let eased = easing.apply(t)
        return start + (target - start) * CGFloat(eased)
    }
}

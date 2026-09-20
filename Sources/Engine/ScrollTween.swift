import CoreGraphics

class ScrollTween {
    private var start: CGFloat
    private var target: CGFloat
    private let totalFrames: Int
    private let easing: Easing
    private var currentFrame: Int = 0

    init(
        from start: CGFloat,
        to target: CGFloat,
        totalFrames: Int = 12,
        easing: Easing = .easeOut
    ) {
        self.start = start
        self.target = target
        self.totalFrames = totalFrames
        self.easing = easing
    }

    func aim(from current: CGFloat, by delta: CGFloat, within bounds: ClosedRange<CGFloat>) {
        start = current
        target = min(max(target + delta, bounds.lowerBound), bounds.upperBound)
        currentFrame = 0
    }

    func nextValue() -> CGFloat? {
        currentFrame += 1
        if currentFrame > totalFrames { return nil }
        let t: Double = Double(currentFrame) / Double(totalFrames)
        let eased: Double = easing.apply(t)
        return start + (target - start) * CGFloat(eased)
    }
}

import CoreGraphics

class ScrollTween {
    private var start: CGFloat
    private var target: CGFloat
    private let numFrames: Int
    private let easing: Easing
    private var frameCount: Int = 0

    init(
        from start: CGFloat, to target: CGFloat, numFrames: Int = 12,
        easing: Easing = .easeOut
    ) {
        self.start = start
        self.target = target
        self.numFrames = numFrames
        self.easing = easing
    }

    func aim(from current: CGFloat, by delta: CGFloat, within bounds: ClosedRange<CGFloat>) {
        start = current
        target = min(max(target + delta, bounds.lowerBound), bounds.upperBound)
        frameCount = 0
    }

    func nextValue() -> CGFloat? {
        frameCount += 1
        if frameCount > numFrames { return nil }
        let t: Double = Double(frameCount) / Double(numFrames)
        let eased: Double = easing.apply(t)
        return start + (target - start) * CGFloat(eased)
    }
}

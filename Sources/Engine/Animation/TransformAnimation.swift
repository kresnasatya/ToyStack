import CoreGraphics

class TransformAnimation: Animation {
    let animatedProperty: StyleProperty
    private let oldPoint: CGPoint
    private let newPoint: CGPoint
    private let timing: FrameTiming
    private(set) var currentFrame: Int = 0

    init(animatedProperty: StyleProperty, oldPoint: CGPoint, newPoint: CGPoint, timing: FrameTiming) {
        self.animatedProperty = animatedProperty
        self.oldPoint = oldPoint
        self.newPoint = newPoint
        self.timing = timing
    }

    func nextValue() -> AnimatedValue? {
        currentFrame += 1
        if currentFrame > timing.totalFrames { return nil }
        let t: Double = Double(currentFrame) / Double(timing.totalFrames)
        let eased: Double = timing.easing.apply(t)
        let x: CGFloat = oldPoint.x + (newPoint.x - oldPoint.x) * CGFloat(eased)
        let y: CGFloat = oldPoint.y + (newPoint.y - oldPoint.y) * CGFloat(eased)
        return .transform(CGPoint(x: x, y: y))
    }
}

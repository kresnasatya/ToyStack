import CoreGraphics

class TransformAnimation: Animation {
    let animatedProperty: String
    private let oldPoint: CGPoint
    private let newPoint: CGPoint
    private let timing: FrameTiming
    private(set) var currentFrame: Int = 0

    init(animatedProperty: String, oldPoint: CGPoint, newPoint: CGPoint, timing: FrameTiming) {
        self.animatedProperty = animatedProperty
        self.oldPoint = oldPoint
        self.newPoint = newPoint
        self.timing = timing
    }

    func nextValue() -> String? {
        currentFrame += 1
        if currentFrame > timing.totalFrames { return nil }
        let t: Double = Double(currentFrame) / Double(timing.totalFrames)
        let eased: Double = timing.easing.apply(t)
        let x: Double = Double(oldPoint.x) + Double(newPoint.x - oldPoint.x) * eased
        let y: Double = Double(oldPoint.y) + Double(newPoint.y - oldPoint.y) * eased
        return "translate(\(x)px, \(y)px)"
    }
}

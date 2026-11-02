import CoreGraphics

class NumericAnimation: Animation {
    let oldValue: Double
    let newValue: Double
    let timing: FrameTiming
    let animatedProperty: StyleProperty
    private(set) var currentFrame: Int = 0

    init(animatedProperty: StyleProperty, oldValue: Double, newValue: Double, timing: FrameTiming) {
        self.animatedProperty = animatedProperty
        self.oldValue = oldValue
        self.newValue = newValue
        self.timing = timing
    }

    func nextValue() -> AnimatedValue? {
        currentFrame += 1
        if currentFrame > timing.totalFrames { return nil }
        let t: Double = Double(currentFrame) / Double(timing.totalFrames)
        let eased: Double = timing.easing.apply(t)
        let current: Double = oldValue + (newValue - oldValue) * eased
        return .number(current)
    }
}

class PixelAnimation: NumericAnimation {
    override func nextValue() -> AnimatedValue? {
        guard let value = super.nextValue() else { return nil }
        guard case .number(let number) = value else { return nil }
        return .length(CGFloat(number))
    }
}

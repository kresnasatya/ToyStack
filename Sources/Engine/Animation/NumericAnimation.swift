class NumericAnimation: Animation {
    let oldValue: Double
    let newValue: Double
    let timing: FrameTiming
    let animatedProperty: String
    private(set) var currentFrame: Int = 0
    private let changePerFrame: Double

    init(animatedProperty: String, oldValue: Double, newValue: Double, timing: FrameTiming) {
        self.animatedProperty = animatedProperty
        self.oldValue = oldValue
        self.newValue = newValue
        self.timing = timing
        self.changePerFrame = (newValue - oldValue) / Double(timing.totalFrames)
    }

    func nextValue() -> String? {
        currentFrame += 1
        if currentFrame > timing.totalFrames { return nil }
        let t: Double = Double(currentFrame) / Double(timing.totalFrames)
        let eased: Double = timing.easing.apply(t)
        let current: Double = oldValue + (newValue - oldValue) * eased
        return String(current)
    }
}

class PixelAnimation: NumericAnimation {
    override func nextValue() -> String? {
        guard let value = super.nextValue() else { return nil }
        return value + "px"
    }
}

class NumericAnimation: Animation {
    let oldValue: Double
    let newValue: Double
    let spec: TransitionSpec
    let animatedProperty: String
    private(set) var frameCount: Int = 1
    private let changePerFrame: Double

    init(animatedProperty: String, oldValue: Double, newValue: Double, spec: TransitionSpec) {
        self.animatedProperty = animatedProperty
        self.oldValue = oldValue
        self.newValue = newValue
        self.spec = spec
        self.changePerFrame = (newValue - oldValue) / Double(spec.numFrames)
    }

    func nextValue() -> String? {
        frameCount += 1
        if frameCount > spec.numFrames { return nil }
        let t: Double = Double(frameCount) / Double(spec.numFrames)
        let eased: Double = spec.easing.apply(t)
        let current: Double = oldValue + (newValue - oldValue) * eased
        return String(current)
    }
}

class PixelAnimation: NumericAnimation {
    init?(animatedProperty: String, oldValue: String, newValue: String, spec: TransitionSpec) {
        guard let old = PixelAnimation.parsePx(oldValue),
            let new = PixelAnimation.parsePx(newValue)
        else { return nil }
        super.init(animatedProperty: animatedProperty, oldValue: old, newValue: new, spec: spec)
    }

    override func nextValue() -> String? {
        guard let value = super.nextValue() else { return nil }
        return value + "px"
    }

    private static func parsePx(_ value: String) -> Double? {
        guard value.hasSuffix("px") else { return nil }
        return Double(value.dropLast(2))
    }
}

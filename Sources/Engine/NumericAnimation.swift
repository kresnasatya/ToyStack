class NumericAnimation: Animation {
    let oldValue: Double
    let newValue: Double
    let numFrames: Int
    let easing: EasingFunction
    private(set) var frameCount: Int = 1
    private let changePerFrame: Double

    init(oldValue: Double, newValue: Double, numFrames: Int, easing: EasingFunction = .ease) {
        self.oldValue = oldValue
        self.newValue = newValue
        self.numFrames = numFrames
        self.easing = easing
        self.changePerFrame = (newValue - oldValue) / Double(numFrames)
    }

    func animate() -> String? {
        frameCount += 1
        if frameCount > numFrames { return nil }
        let t: Double = Double(frameCount) / Double(numFrames)
        let eased: Double = easing.apply(t)
        let current: Double = oldValue + (newValue - oldValue) * eased
        return String(current)
    }
}

class PixelAnimation: NumericAnimation {
    init?(oldValue: String, newValue: String, numFrames: Int, easing: EasingFunction = .ease) {
        guard let old = PixelAnimation.parsePx(oldValue),
            let new = PixelAnimation.parsePx(newValue)
        else { return nil }
        super.init(oldValue: old, newValue: new, numFrames: numFrames, easing: easing)
    }

    override func animate() -> String? {
        guard let value = super.animate() else { return nil }
        return value + "px"
    }

    private static func parsePx(_ value: String) -> Double? {
        guard value.hasSuffix("px") else { return nil }
        return Double(value.dropLast(2))
    }
}

typealias RGBColor = (r: Double, g: Double, b: Double)

func rgbToHex(_ r: Double, _ g: Double, _ b: Double) -> String {
    func clamp(_ v: Double) -> Int { max(0, min(255, Int(v.rounded()))) }
    return String(format: "#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
}

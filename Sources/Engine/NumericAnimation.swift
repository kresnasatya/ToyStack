protocol Animation: AnyObject {
    func animate() -> String?
}

class NumericAnimation: Animation {
    let oldValue: Double
    let newValue: Double
    let numFrames: Int
    private(set) var frameCount: Int = 1
    private let changePerFrame: Double

    init(oldValue: Double, newValue: Double, numFrames: Int) {
        self.oldValue = oldValue
        self.newValue = newValue
        self.numFrames = numFrames
        self.changePerFrame = (newValue - oldValue) / Double(numFrames)
    }

    func animate() -> String? {
        frameCount += 1
        if frameCount >= numFrames { return nil }
        let current = oldValue + changePerFrame * Double(frameCount)
        return String(current)
    }
}

typealias RGBColor = (r: Double, g: Double, b: Double)

class ColorAnimation: Animation {
    let oldColor: RGBColor
    let newColor: RGBColor
    let numFrames: Int
    private(set) var frameCount: Int = 1
    private let changePerFrame: RGBColor

    init(oldColor: RGBColor, newColor: RGBColor, numFrames: Int) {
        self.oldColor = oldColor
        self.newColor = newColor
        self.numFrames = numFrames
        self.changePerFrame = (
            (newColor.r - oldColor.r) / Double(numFrames),
            (newColor.g - oldColor.g) / Double(numFrames),
            (newColor.b - oldColor.b) / Double(numFrames)
        )
    }

    func animate() -> String? {
        frameCount += 1
        if frameCount >= numFrames { return nil }
        let f = Double(frameCount)
        let r = oldColor.r + changePerFrame.r * f
        let g = oldColor.g + changePerFrame.g * f
        let b = oldColor.b + changePerFrame.b * f
        return rgbToHex(r, g, b)
    }
}

func rgbToHex(_ r: Double, _ g: Double, _ b: Double) -> String {
    func clamp(_ v: Double) -> Int { max(0, min(255, Int(v.rounded()))) }
    return String(format: "#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
}

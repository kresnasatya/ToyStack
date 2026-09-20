class ColorAnimation: Animation {
    let animatedProperty: String
    let oldColor: RGBColor
    let newColor: RGBColor
    let timing: FrameTiming
    private(set) var currentFrame: Int = 0
    private let changePerFrame: RGBColor

    init(animatedProperty: String, oldColor: RGBColor, newColor: RGBColor, timing: FrameTiming) {
        self.animatedProperty = animatedProperty
        self.oldColor = oldColor
        self.newColor = newColor
        self.timing = timing
        self.changePerFrame = (
            (newColor.r - oldColor.r) / Double(timing.totalFrames),
            (newColor.g - oldColor.g) / Double(timing.totalFrames),
            (newColor.b - oldColor.b) / Double(timing.totalFrames)
        )
    }

    func nextValue() -> String? {
        currentFrame += 1
        if currentFrame > timing.totalFrames { return nil }
        let t: Double = Double(currentFrame) / Double(timing.totalFrames)
        let eased: Double = timing.easing.apply(t)
        let r: Double = oldColor.r + (newColor.r - oldColor.r) * eased
        let g: Double = oldColor.g + (newColor.g - oldColor.g) * eased
        let b: Double = oldColor.b + (newColor.b - oldColor.b) * eased
        return rgbToHex(r, g, b)
    }
}

class ColorAnimation: Animation {
    let animatedProperty: String
    let oldColor: RGBColor
    let newColor: RGBColor
    let spec: TransitionSpec
    private(set) var frameCount: Int = 1
    private let changePerFrame: RGBColor

    init(animatedProperty: String, oldColor: RGBColor, newColor: RGBColor, spec: TransitionSpec) {
        self.animatedProperty = animatedProperty
        self.oldColor = oldColor
        self.newColor = newColor
        self.spec = spec
        self.changePerFrame = (
            (newColor.r - oldColor.r) / Double(spec.numFrames),
            (newColor.g - oldColor.g) / Double(spec.numFrames),
            (newColor.b - oldColor.b) / Double(spec.numFrames)
        )
    }

    func nextValue() -> String? {
        frameCount += 1
        if frameCount > spec.numFrames { return nil }
        let t: Double = Double(frameCount) / Double(spec.numFrames)
        let eased: Double = spec.easing.apply(t)
        let r: Double = oldColor.r + (newColor.r - oldColor.r) * eased
        let g: Double = oldColor.g + (newColor.g - oldColor.g) * eased
        let b: Double = oldColor.b + (newColor.b - oldColor.b) * eased
        return rgbToHex(r, g, b)
    }
}

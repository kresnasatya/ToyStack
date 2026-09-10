class ColorAnimation: Animation {
    let oldColor: RGBColor
    let newColor: RGBColor
    let numFrames: Int
    let easing: EasingFunction
    private(set) var frameCount: Int = 1
    private let changePerFrame: RGBColor

    init(oldColor: RGBColor, newColor: RGBColor, numFrames: Int, easing: EasingFunction = .ease) {
        self.oldColor = oldColor
        self.newColor = newColor
        self.numFrames = numFrames
        self.easing = easing
        self.changePerFrame = (
            (newColor.r - oldColor.r) / Double(numFrames),
            (newColor.g - oldColor.g) / Double(numFrames),
            (newColor.b - oldColor.b) / Double(numFrames)
        )
    }

    func animate() -> String? {
        frameCount += 1
        if frameCount > numFrames { return nil }
        let t = Double(frameCount) / Double(numFrames)
        let eased = easing.apply(t)
        let r = oldColor.r + (newColor.r - oldColor.r) * eased
        let g = oldColor.g + (newColor.g - oldColor.g) * eased
        let b = oldColor.b + (newColor.b - oldColor.b) * eased
        return rgbToHex(r, g, b)
    }
}

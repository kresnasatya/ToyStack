class ColorAnimation: Animation {
    let animatedProperty: StyleProperty
    let oldColor: BrowserColor
    let newColor: BrowserColor
    let timing: FrameTiming
    private(set) var currentFrame: Int = 0

    init(animatedProperty: StyleProperty, oldColor: BrowserColor, newColor: BrowserColor, timing: FrameTiming) {
        self.animatedProperty = animatedProperty
        self.oldColor = oldColor
        self.newColor = newColor
        self.timing = timing
    }

    func nextValue() -> AnimatedValue? {
        currentFrame += 1
        if currentFrame > timing.totalFrames { return nil }
        let t: Double = Double(currentFrame) / Double(timing.totalFrames)
        let eased: Double = timing.easing.apply(t)
        return .color(BrowserColor(
            red: oldColor.red + (newColor.red - oldColor.red) * eased,
            green: oldColor.green + (newColor.green - oldColor.green) * eased,
            blue: oldColor.blue + (newColor.blue - oldColor.blue) * eased,
            alpha: 1
        ))
    }
}

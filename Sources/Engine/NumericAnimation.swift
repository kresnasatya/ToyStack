class NumericAnimation {
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

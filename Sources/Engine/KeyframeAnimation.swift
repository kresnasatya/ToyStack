struct KeyframeTiming {
    let spec: TransitionSpec
    let infinite: Bool
    let alternate: Bool
}

struct KeyframeRange {
    let from: String
    let to: String
}

class KeyframeAnimation: Animation {
    let animatedProperty: String
    private let infinite: Bool
    private let alternate: Bool
    private let numFrames: Int
    private let easing: EasingFunction
    private let oldValue: String
    private let newValue: String
    private let factory: (String, String, Int, EasingFunction) -> Animation?
    private var inner: Animation
    private var reversed: Bool = false

    init(
        animatedProperty: String,
        range: KeyframeRange,
        timing: KeyframeTiming,
        factory: @escaping (String, String, Int, EasingFunction) -> Animation?
    ) {
        self.animatedProperty = animatedProperty
        self.oldValue = range.from
        self.newValue = range.to
        self.numFrames = timing.spec.numFrames
        self.easing = timing.spec.easing
        self.infinite = timing.infinite
        self.alternate = timing.alternate
        self.factory = factory
        self.inner = factory(range.from, range.to, timing.spec.numFrames, timing.spec.easing)!
    }

    func animate() -> String? {
        if let value = inner.animate() {
            return value
        }
        guard infinite else { return nil }

        if alternate {
            reversed.toggle()
            let from = reversed ? newValue : oldValue
            let to = reversed ? oldValue : newValue
            inner = factory(from, to, numFrames, easing) ?? inner
        } else {
            inner = factory(oldValue, newValue, numFrames, easing) ?? inner
        }
        return inner.animate()
    }
}

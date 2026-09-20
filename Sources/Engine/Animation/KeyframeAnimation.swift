struct KeyframeRange {
    let from: AnimatedValue
    let to: AnimatedValue
}

class KeyframeAnimation: Animation {
    let animatedProperty: String
    private let infinite: Bool
    private let alternate: Bool
    private let totalFrames: Int
    private let easing: Easing
    private let oldValue: AnimatedValue
    private let newValue: AnimatedValue
    private let factory: (AnimatedValue, AnimatedValue, Int, Easing) -> Animation?
    private var inner: Animation
    private var reversed: Bool = false

    init(
        animatedProperty: String,
        range: KeyframeRange,
        playback: KeyframePlayback,
        factory: @escaping (AnimatedValue, AnimatedValue, Int, Easing) -> Animation?
    ) {
        self.animatedProperty = animatedProperty
        self.oldValue = range.from
        self.newValue = range.to
        self.totalFrames = playback.totalFrames
        self.easing = .ease
        self.infinite = playback.infinite
        self.alternate = playback.alternate
        self.factory = factory
        self.inner = factory(range.from, range.to, playback.totalFrames, .ease)!
    }

    func nextValue() -> String? {
        if let value = inner.nextValue() {
            return value
        }
        guard infinite else { return nil }

        if alternate {
            reversed.toggle()
            let from: AnimatedValue = reversed ? newValue : oldValue
            let to: AnimatedValue = reversed ? oldValue : newValue
            inner = factory(from, to, totalFrames, easing) ?? inner
        } else {
            inner = factory(oldValue, newValue, totalFrames, easing) ?? inner
        }
        return inner.nextValue()
    }
}

extension KeyframeAnimation {
    static func make(
        frames: [Keyframe],
        playback: KeyframePlayback
    ) -> KeyframeAnimation? {
        guard let from = frames.first(where: { $0.offset == 0.0 }),
            let to = frames.first(where: { $0.offset == 1.0 })
        else { return nil }

        let differing: [String : String] = from.body.filter { to.body[$0.key] != $0.value }
        guard let (property, oldVal) = differing.first, let newVal = to.body[property]
        else { return nil }

        guard let oldValue = AnimatedValue(css: oldVal, property: property),
            let newValue = AnimatedValue(css: newVal, property: property)
        else { return nil }

        let factory: (AnimatedValue, AnimatedValue, Int, Easing) -> Animation?
        switch (oldValue, newValue) {
        case (.number(let o), .number(let n)):
            factory = { _, _, tf, e in NumericAnimation(animatedProperty: property, oldValue: o, newValue: n, timing: FrameTiming(totalFrames: tf, easing: e)) }
        case (.length(let o), .length(let n)):
            factory = { _, _, tf, e in PixelAnimation(animatedProperty: property, oldValue: o, newValue: n, timing: FrameTiming(totalFrames: tf, easing: e)) }
        case (.color(let o), .color(let n)):
            factory = { _, _, tf, e in ColorAnimation(animatedProperty: property, oldColor: o, newColor: n, timing: FrameTiming(totalFrames: tf, easing: e)) }
        default:
            return nil
        }

        return KeyframeAnimation(
            animatedProperty: property,
            range: KeyframeRange(from: oldValue, to: newValue),
            playback: playback,
            factory: factory
        )
    }
}

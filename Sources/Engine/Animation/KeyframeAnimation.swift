struct KeyframeTiming {
    let transition: TransitionSpec
    let infinite: Bool
    let alternate: Bool
}

struct KeyframeRange {
    let from: AnimatedValue
    let to: AnimatedValue
}

class KeyframeAnimation: Animation {
    let animatedProperty: String
    private let infinite: Bool
    private let alternate: Bool
    private let numFrames: Int
    private let easing: Easing
    private let oldValue: AnimatedValue
    private let newValue: AnimatedValue
    private let factory: (AnimatedValue, AnimatedValue, Int, Easing) -> Animation?
    private var inner: Animation
    private var reversed: Bool = false

    init(
        animatedProperty: String,
        range: KeyframeRange,
        timing: KeyframeTiming,
        factory: @escaping (AnimatedValue, AnimatedValue, Int, Easing) -> Animation?
    ) {
        self.animatedProperty = animatedProperty
        self.oldValue = range.from
        self.newValue = range.to
        self.numFrames = timing.transition.numFrames
        self.easing = timing.transition.easing
        self.infinite = timing.infinite
        self.alternate = timing.alternate
        self.factory = factory
        self.inner = factory(range.from, range.to, timing.transition.numFrames, timing.transition.easing)!
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
            inner = factory(from, to, numFrames, easing) ?? inner
        } else {
            inner = factory(oldValue, newValue, numFrames, easing) ?? inner
        }
        return inner.nextValue()
    }
}

extension KeyframeAnimation {
    static func make(
        frames: [Keyframe],
        numFrames: Int,
        infinite: Bool,
        alternate: Bool
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
            factory = { _, _, nf, e in NumericAnimation(animatedProperty: property, oldValue: o, newValue: n, spec: TransitionSpec(numFrames: nf, easing: e)) }
        case (.length(let o), .length(let n)):
            factory = { _, _, nf, e in PixelAnimation(animatedProperty: property, oldValue: o, newValue: n, spec: TransitionSpec(numFrames: nf, easing: e)) }
        case (.color(let o), .color(let n)):
            factory = { _, _, nf, e in ColorAnimation(animatedProperty: property, oldColor: o, newColor: n, spec: TransitionSpec(numFrames: nf, easing: e)) }
        default:
            return nil
        }

        return KeyframeAnimation(
            animatedProperty: property,
            range: KeyframeRange(from: oldValue, to: newValue),
            timing: KeyframeTiming(
                transition: TransitionSpec(numFrames: numFrames, easing: .ease),
                infinite: infinite,
                alternate: alternate
            ),
            factory: factory
        )
    }
}

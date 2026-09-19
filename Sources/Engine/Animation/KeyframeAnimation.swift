struct KeyframeTiming {
    let transition: TransitionSpec
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
    private let easing: Easing
    private let oldValue: String
    private let newValue: String
    private let factory: (String, String, Int, Easing) -> Animation?
    private var inner: Animation
    private var reversed: Bool = false

    init(
        animatedProperty: String,
        range: KeyframeRange,
        timing: KeyframeTiming,
        factory: @escaping (String, String, Int, Easing) -> Animation?
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
            let from: String = reversed ? newValue : oldValue
            let to: String = reversed ? oldValue : newValue
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

        let factory: (String, String, Int, Easing) -> Animation?
        switch property {
        case "opacity":
            factory = { old, new, nf, e in
                guard let o = Double(old), let n = Double(new) else { return nil }
                return NumericAnimation(oldValue: o, newValue: n, numFrames: nf, easing: e)
            }
        case "width", "height":
            factory = { old, new, nf, e in
                PixelAnimation(oldValue: old, newValue: new, numFrames: nf, easing: e)
            }
        case "background-color":
            factory = { old, new, nf, e in
                guard let o = cssColorToRGB(old), let n = cssColorToRGB(new) else { return nil }
                return ColorAnimation(oldColor: o, newColor: n, numFrames: nf, easing: e)
            }
        default:
            return nil
        }

        return KeyframeAnimation(
            animatedProperty: property,
            range: KeyframeRange(from: oldVal, to: newVal),
            timing: KeyframeTiming(
                transition: TransitionSpec(numFrames: numFrames, easing: .ease),
                infinite: infinite,
                alternate: alternate
            ),
            factory: factory
        )
    }
}

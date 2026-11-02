@MainActor
enum StyleTransitions {
    static func diff(
        node: DOMRef,
        oldStyle: ComputedStyle,
        newStyle: ComputedStyle
    ) -> [StyleProperty: Animation] {
        var animations: [StyleProperty: Animation] = [:]
        let transitions: [String: FrameTiming] =
            FrameTiming.parse(node.style.unknownValue("transition") ?? "")
        for (property, timing) in transitions {
            guard let key = StyleProperty(cssName: property),
                let oldValue = oldStyle.value(for: key),
                let newValue = newStyle.value(for: key),
                oldValue != newValue,
                let animation = makeAnimation(
                    property: key,
                    oldValue: oldValue,
                    newValue: newValue,
                    timing: timing
                )
            else { continue }
            animations[key] = animation
            node.style.set(oldValue, for: key)
        }
        return animations
    }

    private static func makeAnimation(
        property: StyleProperty,
        oldValue: AnimatedValue,
        newValue: AnimatedValue,
        timing: FrameTiming
    ) -> Animation? {
        switch (oldValue, newValue) {
        case (.number(let o), .number(let n)):
            return NumericAnimation(
                animatedProperty: property,
                oldValue: o,
                newValue: n,
                timing: timing
            )
        case (.length(let o), .length(let n)):
            return PixelAnimation(
                animatedProperty: property,
                oldValue: Double(o),
                newValue: Double(n),
                timing: timing
            )
        case (.color(let o), .color(let n)):
            return ColorAnimation(
                animatedProperty: property,
                oldColor: o,
                newColor: n,
                timing: timing
            )
        case (.transform(let o), .transform(let n)):
            return TransformAnimation(
                animatedProperty: property,
                oldPoint: o,
                newPoint: n,
                timing: timing
            )
        default:
            return nil
        }
    }
}

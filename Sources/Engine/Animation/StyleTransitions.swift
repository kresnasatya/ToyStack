enum StyleTransitions {
    static func diff(node: DOMNode, oldStyle: [String: String], newStyle: [String: String]) -> [String: Animation]
    {
        var animations: [String: Animation] = [:]
        let transitions: [String : FrameTiming] = FrameTiming.parse(newStyle["transition"] ?? "")
        for (property, timing) in transitions {
            guard let oldValue = oldStyle[property],
                let newValue = newStyle[property],
                oldValue != newValue,
                let animation = makeAnimation(property: property, oldValue: oldValue, newValue: newValue, timing: timing)
            else { continue }
            animations[property] = animation
            node.style[property] = oldValue
        }
        return animations
    }

    private static func makeAnimation(
        property: String,
        oldValue: String,
        newValue: String,
        timing: FrameTiming
    ) -> Animation? {
        if property == "transform", let oldPoint = CSSValueParser.transform(oldValue),
            let newPoint = CSSValueParser.transform(newValue)
        {
            return TransformAnimation(
                animatedProperty: property,
                oldPoint: oldPoint,
                newPoint: newPoint,
                timing: timing
            )
        }
        guard let old = AnimatedValue(css: oldValue, property: property),
            let new = AnimatedValue(css: newValue, property: property)
        else { return nil }
        switch (old, new) {
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
                oldValue: o,
                newValue: n,
                timing: timing
            )
        case (.color(let o), .color(let n)):
            return ColorAnimation(
                animatedProperty: property,
                oldColor: o,
                newColor: n,
                timing: timing
            )
        default:
            return nil
        }
    }
}

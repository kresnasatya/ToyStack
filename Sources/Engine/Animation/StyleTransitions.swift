func diffStyles(node: DOMNode, oldStyle: [String: String], newStyle: [String: String]) -> [String:
    Animation]
{
    var animations: [String: Animation] = [:]
    let transitions: [String : FrameTiming] = FrameTiming.parse(newStyle["transition"] ?? "")
    for (property, timing) in transitions {
        guard let oldVal = oldStyle[property],
            let newVal = newStyle[property],
            oldVal != newVal
        else { continue }
        if property == "opacity", let old = Double(oldVal), let new = Double(newVal) {
            animations[property] = NumericAnimation(
                animatedProperty: property,
                oldValue: old,
                newValue: new,
                timing: timing
            )
            node.style[property] = oldVal
        } else if property == "transform", let oldPoint = parseTransform(oldVal),
            let newPoint = parseTransform(newVal)
        {
            animations["transform-x"] = NumericAnimation(
                animatedProperty: property,
                oldValue: Double(oldPoint.x),
                newValue: Double(newPoint.x),
                timing: timing
            )
            animations["transform-y"] = NumericAnimation(
                animatedProperty: property,
                oldValue: Double(oldPoint.y),
                newValue: Double(newPoint.y),
                timing: timing
            )
            node.style[property] = oldVal
        } else if property == "background-color",
            let old = cssColorToRGB(oldVal),
            let new = cssColorToRGB(newVal)
        {
            animations[property] = ColorAnimation(
                animatedProperty: property,
                oldColor: old,
                newColor: new,
                timing: timing
            )
            node.style[property] = oldVal
        } else if property == "width" || property == "height",
            let old = AnimatedValue(css: oldVal, property: property)?.length,
            let new = AnimatedValue(css: newVal, property: property)?.length
        {
            animations[property] = PixelAnimation(
                animatedProperty: property,
                oldValue: old,
                newValue: new,
                timing: timing
            )
            node.style[property] = oldVal
        }
    }
    return animations
}

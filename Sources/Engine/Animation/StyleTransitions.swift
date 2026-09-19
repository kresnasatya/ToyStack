func diffStyles(node: DOMNode, oldStyle: [String: String], newStyle: [String: String]) -> [String:
    Animation]
{
    var animations: [String: Animation] = [:]
    let transitions: [String : TransitionSpec] = parseTransition(newStyle["transition"] ?? "")
    for (property, spec) in transitions {
        let numFrames: Int = spec.numFrames
        guard let oldVal = oldStyle[property],
            let newVal = newStyle[property],
            oldVal != newVal
        else { continue }
        if property == "opacity", let old = Double(oldVal), let new = Double(newVal) {
            animations[property] = NumericAnimation(
                oldValue: old, newValue: new, numFrames: numFrames, easing: spec.easing)
            node.style[property] = oldVal
        } else if property == "transform", let oldPoint = parseTransform(oldVal),
            let newPoint = parseTransform(newVal)
        {
            animations["transform-x"] = NumericAnimation(
                oldValue: Double(oldPoint.x), newValue: Double(newPoint.x), numFrames: numFrames,
                easing: spec.easing)
            animations["transform-y"] = NumericAnimation(
                oldValue: Double(oldPoint.y), newValue: Double(newPoint.y), numFrames: numFrames,
                easing: spec.easing)
            node.style[property] = oldVal
        } else if property == "background-color",
            let old = cssColorToRGB(oldVal),
            let new = cssColorToRGB(newVal)
        {
            animations[property] = ColorAnimation(
                oldColor: old, newColor: new, numFrames: numFrames, easing: spec.easing)
            node.style[property] = oldVal
        } else if property == "width" || property == "height",
            let anim = PixelAnimation(
                oldValue: oldVal, newValue: newVal, numFrames: numFrames, easing: spec.easing)
        {
            animations[property] = anim
            node.style[property] = oldVal
        }
    }
    return animations
}

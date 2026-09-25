func focusRingColors(_ node: any DOMNode) -> (outer: String, inner: String) {
    isForcedColors(node)
        ? (ForcedColor.highlight, ForcedColor.canvas)
        : ("white", "black")
}

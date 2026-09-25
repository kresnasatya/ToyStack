func focusRingColors(_ node: any DOMNode) -> (outer: String, inner: String) {
    usesForcedColors(node)
        ? (ForcedColor.highlight, ForcedColor.canvas)
        : ("white", "black")
}

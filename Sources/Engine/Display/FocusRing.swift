@MainActor
func focusRingColors(_ node: DOMRef) -> (outer: String, inner: String) {
    usesForcedColors(node)
        ? (ForcedColor.highlight, ForcedColor.canvas)
        : ("white", "black")
}

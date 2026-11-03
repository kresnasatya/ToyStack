func focusRingColors(forcedColors: Bool) -> (outer: String, inner: String) {
    forcedColors
        ? (ForcedColor.highlight, ForcedColor.canvas)
        : ("white", "black")
}

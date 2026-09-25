struct ColorPreferences: Equatable {
    var prefersDark: Bool
    var usesForcedColors: Bool

    var defaultTextColor: String {
        usesForcedColors ? ForcedColor.canvasText : (prefersDark ? "white" : "black")
    }
}

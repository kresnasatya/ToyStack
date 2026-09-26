import CoreGraphics

struct MediaFeatures {
    let preferences: ColorPreferences
    let frameWidth: CGFloat

    func matches(_ query: String?) -> Bool {
        guard let m = query else { return true }
        switch m {
            case "dark": return preferences.prefersDark
            case "light": return !preferences.prefersDark
            case "forced-colors:active": return preferences.usesForcedColors
            case "forced-colors:none": return !preferences.usesForcedColors
            default:
                if m.hasPrefix("max-width:") {
                    let limit: Double = Double(m.dropFirst("max-width:".count)) ?? 0
                    return frameWidth <= CGFloat(limit)
                }
                return false
        }
    }
}

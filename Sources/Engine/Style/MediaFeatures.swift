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
            return matchesWidth(m)
        }
    }

    private func matchesWidth(_ query: String) -> Bool {
        let parts: [Substring] = query.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let limit = Double(parts[1]) else { return false }
        let width: CGFloat = CGFloat(limit)
        switch parts[0] {
        case "max-width": return frameWidth <= width
        case "min-width": return frameWidth >= width
        case "width": return frameWidth == width
        default: return false
        }
    }
}

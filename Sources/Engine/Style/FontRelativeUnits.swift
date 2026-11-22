import CoreGraphics
import CoreText

// MARK: - FontRelativeUnits

/// CSS Values 4 §6.1.1: em, ex, and ch measure the element's own font, so a
/// length in those units becomes px once the element's font-size is known.
struct FontRelativeUnits {
    let font: TextStyle.Font

    func px(_ raw: String?) -> CGFloat? {
        guard let raw, let value = Double(raw.dropLast(2)) else { return nil }
        let amount: CGFloat = CGFloat(value)
        switch raw.suffix(2) {
        case "px": return amount
        case "em": return amount * font.size
        case "ex": return amount * scaledMetric({ CTFontGetXHeight($0.ctFont) })
        case "ch": return amount * scaledMetric({ $0.measure("0") })
        default: return nil
        }
    }

    static func isFontRelative(_ raw: String) -> Bool {
        return raw.hasSuffix("em") || raw.hasSuffix("ex") || raw.hasSuffix("ch")
    }

    private func scaledMetric(_ metric: (BrowserFont) -> CGFloat) -> CGFloat {
        let wholeSize: Int = max(1, Int(font.size.rounded()))
        let browserFont: BrowserFont = getFont(
            size: wholeSize,
            weight: font.weight.cssValue,
            style: font.style.browserFontStyle,
            family: font.family
        )
        return metric(browserFont) * font.size / CGFloat(wholeSize)
    }
}

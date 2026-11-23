import CoreGraphics
import CoreText

// MARK: - RelativeLengths

/// CSS Values 4 §6.1.1: em, ex, and ch measure the element's own font, and rem
/// measures the root element's font, so a length in those units becomes px
/// once the font-size is known.
/// CSS Values 4 §6.1.2: vw and vh are 1% of the viewport's width and height.
/// ToyStack uses the frame's viewport for every viewport size.
struct RelativeLengths {
    let font: TextStyle.Font
    let document: DocumentMetrics

    func px(_ raw: String?) -> CGFloat? {
        guard let raw else { return nil }
        if raw.hasSuffix("rem") {
            guard let value = Double(raw.dropLast(3)) else { return nil }
            return CGFloat(value) * document.rootFontSize
        }
        guard let value = Double(raw.dropLast(2)) else { return nil }
        let amount: CGFloat = CGFloat(value)
        switch raw.suffix(2) {
        case "px": return amount
        case "em": return amount * font.size
        case "ex": return amount * scaledMetric({ CTFontGetXHeight($0.ctFont) })
        case "ch": return amount * scaledMetric({ $0.measure("0") })
        case "vw": return amount * document.viewport.width / 100
        case "vh": return amount * document.viewport.height / 100
        default: return nil
        }
    }

    static func isFontRelative(_ raw: String) -> Bool {
        return raw.hasSuffix("em") || raw.hasSuffix("ex") || raw.hasSuffix("ch")
    }

    static func isViewportRelative(_ raw: String) -> Bool {
        return raw.hasSuffix("vw") || raw.hasSuffix("vh")
    }

    static func isRootRelative(_ raw: String) -> Bool {
        return raw.hasSuffix("rem")
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

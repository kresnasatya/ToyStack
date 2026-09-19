import CoreGraphics
import CoreText
import Foundation

// MARK: - FontMeasureCache
final class FontMeasureCache {
    var widths: [String: CGFloat] = [:]
}

// MARK: - BrowserFont
public struct BrowserFont {
    public let ctFont: CTFont
    let cache: FontMeasureCache

    init(ctFont: CTFont) {
        self.ctFont = ctFont
        self.cache = FontMeasureCache()
    }

    var ascent: CGFloat {
        CTFontGetAscent(ctFont)
    }

    var descent: CGFloat {
        CTFontGetDescent(ctFont)
    }

    var leading: CGFloat {
        CTFontGetLeading(ctFont)
    }

    var spaceWidth: CGFloat { measure(" ") }

    public var linespace: CGFloat { ascent + descent + leading }

    public func measure(_ text: String) -> CGFloat {
        profiler.count("text.measureCalls")
        if let cached = cache.widths[text] { return cached }
        profiler.count("text.measureMisses")
        return profiler.measure("text.measure", {
            let attr: NSAttributedString = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont
            ])
            let line: CTLine = CTLineCreateWithAttributedString(attr)
            let width: CGFloat = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            cache.widths[text] = width
            return width
        })
    }
}

// MARK: - Font Cache
nonisolated(unsafe) private var fontCache: [String: BrowserFont] = [:]
let inlineDefaultFont: BrowserFont = getFont(size: 12, weight: "normal", style: "roman")

public func getFont(size: Int, weight: String, style: String, family: String = "serif") -> BrowserFont {
    profiler.count("text.fontRequests")
    return profiler.measure("text.font", {
        let key: String = "\(size)-\(weight)-\(style)-\(family)"
        if let cached = fontCache[key] { return cached }

        var traits: CTFontSymbolicTraits = []
        if weight == "bold" { traits.insert(.traitBold) }
        if style == "italic" { traits.insert(.traitItalic) }

        let ctFont: CTFont
        if family == "monospace" {
            let baseFont: CTFont = CTFontCreateWithName("Courier New" as CFString, CGFloat(size), nil)
            ctFont =
                CTFontCreateCopyWithSymbolicTraits(baseFont, CGFloat(size), nil, traits, traits)
                ?? baseFont
        } else {
            let baseFont: CTFont = CTFontCreateWithName("Georgia" as CFString, CGFloat(size), nil)
            ctFont =
                CTFontCreateCopyWithSymbolicTraits(baseFont, CGFloat(size), nil, traits, traits)
                ?? baseFont
        }

        let font: BrowserFont = BrowserFont(ctFont: ctFont)
        fontCache[key] = font
        return font
    })
}

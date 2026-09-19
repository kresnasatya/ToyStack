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

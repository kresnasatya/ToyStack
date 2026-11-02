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
    let ascent: CGFloat
    let descent: CGFloat
    let leading: CGFloat
    let spaceWidth: CGFloat

    init(ctFont: CTFont) {
        self.ctFont = ctFont
        self.cache = FontMeasureCache()
        self.ascent = CTFontGetAscent(ctFont)
        self.descent = CTFontGetDescent(ctFont)
        self.leading = CTFontGetLeading(ctFont)
        self.spaceWidth = BrowserFont.spaceWidth(for: ctFont)
    }

    private static func spaceWidth(for ctFont: CTFont) -> CGFloat {
        let attr: NSAttributedString = NSAttributedString(string: " ", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont
        ])
        let line: CTLine = CTLineCreateWithAttributedString(attr)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

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
let inlineDefaultFont: BrowserFont = getFont(size: 16, weight: "normal", style: "roman")

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

@MainActor
func fontInputs(for node: DOMRef) -> [any InvalidatableField] {
    let owner: DOMRef = node.inheritedStyleOwner
    return [
        owner.style.field(.fontWeight),
        owner.style.field(.fontStyle),
        owner.style.field(.fontSize),
        owner.style.field(.fontFamily),
    ]
}

@MainActor
func fontForElement(_ node: DOMRef, zoom: CGFloat, notify: any InvalidatableField) -> BrowserFont {
    let owner: DOMRef = node.inheritedStyleOwner
    owner.style.field(.fontWeight).touch(notify)
    owner.style.field(.fontStyle).touch(notify)
    owner.style.field(.fontSize).touch(notify)
    owner.style.field(.fontFamily).touch(notify)
    let font: TextStyle.Font = owner.style.computed.text.font
    let sizeInt: Int = Int(font.size * zoom)
    return getFont(
        size: sizeInt,
        weight: font.weight.cssValue,
        style: font.style.browserFontStyle,
        family: font.family
    )
}

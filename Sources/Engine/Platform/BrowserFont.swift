import CoreGraphics
import CoreText
import Foundation

// MARK: - FontMeasureCache
final class FontMeasureCache: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var widths: [String: CGFloat] = [:]

    func width(for text: String, compute: () -> CGFloat) -> CGFloat {
        lock.lock()
        if let cached: CGFloat = widths[text] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let width: CGFloat = compute()

        lock.lock()
        widths[text] = width
        lock.unlock()
        return width
    }
}

// MARK: - BrowserFont
// CTFont is immutable but CoreText does not annotate it. The measure cache is
// locked, so the value is safe to send.
public struct BrowserFont: @unchecked Sendable {
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
    var size: CGFloat { CTFontGetSize(ctFont) }

    public func measure(_ text: String) -> CGFloat {
        profiler.count("text.measureCalls")
        return cache.width(for: text) {
            profiler.count("text.measureMisses")
            return profiler.measure("text.measure", {
                let attr: NSAttributedString = NSAttributedString(string: text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): ctFont
                ])
                let line: CTLine = CTLineCreateWithAttributedString(attr)
                return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            })
        }
    }
}

// MARK: - Font Cache
private let fontCacheLock: NSLock = NSLock()
nonisolated(unsafe) private var fontCache: [String: BrowserFont] = [:]
let inlineDefaultFont: BrowserFont = getFont(size: 16, weight: "normal", style: "roman")

public func getFont(size: Int, weight: String, style: String, family: String = "serif") -> BrowserFont {
    profiler.count("text.fontRequests")
    return profiler.measure("text.font", {
        let key: String = "\(size)-\(weight)-\(style)-\(family)"
        fontCacheLock.lock()
        if let cached: BrowserFont = fontCache[key] {
            fontCacheLock.unlock()
            return cached
        }
        fontCacheLock.unlock()

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
        fontCacheLock.lock()
        if let existing: BrowserFont = fontCache[key] {
            fontCacheLock.unlock()
            return existing
        }
        fontCache[key] = font
        fontCacheLock.unlock()
        return font
    })
}

func fontInputs(for id: NodeID, in inputs: LayoutInputs) -> [FieldKey] {
    let owner: NodeID = inputs.inheritedStyleOwner(id)
    return [
        .style(owner, .fontWeight),
        .style(owner, .fontStyle),
        .style(owner, .fontSize),
        .style(owner, .fontFamily),
    ]
}

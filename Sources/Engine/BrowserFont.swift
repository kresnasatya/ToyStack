import CoreGraphics
import CoreText
import Foundation

// MARK: - BrowserFont
public struct BrowserFont {
    public let ctFont: CTFont

    var ascent: CGFloat {
        CTFontGetAscent(ctFont)
    }

    var descent: CGFloat {
        CTFontGetDescent(ctFont)
    }

    var leading: CGFloat {
        CTFontGetLeading(ctFont)
    }

    public var linespace: CGFloat { ascent + descent + leading }

    public func measure(_ text: String) -> CGFloat {
        let start: UInt64 = DispatchTime.now().uptimeNanoseconds
        defer {
            layoutStats.measureCalls += 1
            layoutStats.measureNanos += DispatchTime.now().uptimeNanoseconds - start
        }
        let attr = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont
        ])
        let line = CTLineCreateWithAttributedString(attr)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

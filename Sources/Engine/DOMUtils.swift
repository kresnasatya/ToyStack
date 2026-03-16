import AppKit  // NSAttributedString for text measurement on macOS
import CoreText
import Foundation

// MARK: - Layout Constants
public let WIDTH: CGFloat = 800
public let HEIGHT: CGFloat = 600
public let isRTL: Bool = ProcessInfo.processInfo.arguments.contains("--rtl")
let HSTEP: CGFloat = 13
let VSTEP: CGFloat = 18
let SCROLL_STEP: CGFloat = 100

// MARK: - BrowserFont
// Wraps a CTFont to provide the text metrics the layout engine needs.
// Python used tkinter.font.Font; Swift uses CoreText for the same metrics
struct BrowserFont {
    let ctFont: CTFont

    // Vertical metrics: how far glyphs rise above and descend below the baseline
    var ascent: CGFloat {
        CTFontGetAscent(ctFont)
    }
    var descent: CGFloat {
        CTFontGetDescent(ctFont)
    }
    var leading: CGFloat {
        CTFontGetLeading(ctFont)
    }
    // linespace = total height of one line of text.
    var linespace: CGFloat { ascent + descent + leading }

    // Returns the pixel width of `text` rendered in this font.
    func measure(_ text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: ctFont]
        return (text as NSString).size(withAttributes: attrs).width
    }
}

// MARK: - Font Cache
// Building a CTFont is expensive; cache by (size, weight, style).
nonisolated(unsafe) private var fontCache: [String: BrowserFont] = [:]

nonisolated(unsafe) var visitedURL: Set<String> = []

func getFont(size: Int, weight: String, style: String, family: String = "serif") -> BrowserFont {
    let key = "\(size)-\(weight)-\(style)-\(family)"
    if let cached = fontCache[key] { return cached }

    // Map Python-style strings ("bold", "italic"/"roman") to CoreText traits.
    var traits: CTFontSymbolicTraits = []
    if weight == "bold" { traits.insert(.traitBold) }
    if style == "italic" { traits.insert(.traitItalic) }

    let ctFont: CTFont
    if family == "monospace" {
        let baseFont = CTFontCreateWithName("Courier New" as CFString, CGFloat(size), nil)
        ctFont =
            CTFontCreateCopyWithSymbolicTraits(baseFont, CGFloat(size), nil, traits, traits)
            ?? baseFont
    } else {
        let baseFont = CTFontCreateWithName("Georgia" as CFString, CGFloat(size), nil)
        ctFont =
            CTFontCreateCopyWithSymbolicTraits(baseFont, CGFloat(size), nil, traits, traits)
            ?? baseFont
    }

    let font = BrowserFont(ctFont: ctFont)
    fontCache[key] = font
    return font
}

// MARK: - Inherited CSS Properties
// These defaults are used when a node has no parent (root element)
// and when a property was not set by any CSS rule.
let inheritedProperties: [String: String] = [
    "font-family": "serif",
    "font-size": "16px",
    "font-style": "normal",
    "font-weight": "normal",
    "color": "black",
]

// Precomputes :has() selector-results in single O(n) pass.
// Must be called before applyStyle() before each render cycle.
func precomputeHas(node: any DOMNode, rules: [(any CSSSelector, [String: String])]) {
    let allNodes = treeToList(node)

    // Reset from previous render
    for n in allNodes { n.satisfiedHas = [] }

    let allHasSelectors = rules.flatMap({ $0.0.hasSelectors })
    guard !allHasSelectors.isEmpty else { return }

    // Process in reverse pre-order so children are always handled before parents
    // Reversed pre-order guarantees: when we process node N, all N's children
    // are already processed.
    for n in allNodes.reversed() {
        for hs in allHasSelectors {
            for child in n.children {
                if hs.inner.matches(child) || child.satisfiedHas.contains(hs.id) {
                    n.satisfiedHas.insert(hs.id)
                    break
                }
            }
        }
    }
}

// MARK: - CSS Cascade (style function)
// Walks the entire DOM tree and sets node.style on every node.
// Order of precedence (lowest -> highest):
//   1. Inherited value from parent (or default if at root)
//   2. Matching stylesheet rules (sorted by priority before calling)
//   3. Inline style attribute
func applyStyle(node: any DOMNode, rules: [(any CSSSelector, [String: String])]) {
    node.style = [:]

    // Step 1: start with inherited or default values
    for (property, defaultValue) in inheritedProperties {
        node.style[property] = node.parent?.style[property] ?? defaultValue
    }

    // Step 2: apply all matching CSS rules in cascade order.
    for (selector, body) in rules {
        guard selector.matches(node) else { continue }
        for (property, value) in body {
            node.style[property] = value
        }
    }

    // Step 3: inline style attribute overrides everything.
    if let element = node as? Element,
        let inlineStyle = element.attributes["style"]
    {
        for (property, value) in CSSParser(inlineStyle).body() {
            node.style[property] = value
        }
    }

    // Step 4: resolve percentage font-size relative to parent's px value.
    // e.g. "90%" on a node whose parent has "16px" -> "14.4px"
    if let fontSize = node.style["font-size"], fontSize.hasSuffix("%") {
        let parentFontSize = node.parent?.style["font-size"] ?? inheritedProperties["font-size"]!
        let percentage = Double(fontSize.dropLast()) ?? 100.0
        let parentPx = Double(parentFontSize.dropLast(2)) ?? 16.0
        node.style["font-size"] = "\(percentage / 100.0 * parentPx)px"
    }

    for child in node.children {
        applyStyle(node: child, rules: rules)
    }
}

// MARK: - Cascade Priority
// Used as the sort key when ordering CSS rules before applying them.
func cascadePriority(_ rule: (any CSSSelector, [String: String])) -> Int {
    rule.0.priority
}

// MARK: - Tree Utilities

// Flattens a DOMNode tree into a pre-order (parent before children) list.
func treeToList(_ node: any DOMNode) -> [any DOMNode] {
    var result: [any DOMNode] = [node]
    for child in node.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}

// Flattens a LayoutObject tree into a pre-order list.
func treeToList(_ obj: any LayoutObject) -> [any LayoutObject] {
    var result: [any LayoutObject] = [obj]
    for child in obj.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}

// Walks the layout tree and collects all paint commands into display_list.
func paintTree(_ obj: any LayoutObject, into displayList: inout [any PaintCommand]) {
    if obj.shouldPaint() {
        displayList.append(contentsOf: obj.paint())
    }

    for child in obj.children {
        paintTree(child, into: &displayList)
    }
}

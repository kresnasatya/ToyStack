import AVFoundation
import AppKit  // NSAttributedString for text measurement on macOS
import CoreText
import Foundation
import SwiftUI

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

nonisolated(unsafe) var bookmarks: [String] = []

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
nonisolated(unsafe) var inheritedProperties: [String: String] = [
    "font-family": "serif",
    "font-size": "16px",
    "font-style": "normal",
    "font-weight": "normal",
    "color": "black",
]

// Precomputes :has() selector-results in single O(n) pass.
// Must be called before applyStyle() before each render cycle.
func precomputeHas(node: any DOMNode, rules: [(String?, any CSSSelector, [String: String])]) {
    let allNodes = treeToList(node)

    // Reset from previous render
    for n in allNodes { n.satisfiedHas = [] }

    let allHasSelectors = rules.flatMap({ $0.1.hasSelectors })
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
func applyStyle(
    node: any DOMNode, rules: [(String?, any CSSSelector, [String: String])], darkMode: Bool = false
) {
    node.style = [:]

    // Step 1: start with inherited or default values
    for (property, defaultValue) in inheritedProperties {
        node.style[property] = node.parent?.style[property] ?? defaultValue
    }

    // Step 2: apply all matching CSS rules in cascade order.
    for (media, selector, body) in rules {
        if let m = media {
            if m == "dark" && !darkMode { continue }
            if m == "light" && !darkMode { continue }
        }
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
        applyStyle(node: child, rules: rules, darkMode: darkMode)
    }
}

// MARK: - Cascade Priority
// Used as the sort key when ordering CSS rules before applying them.
func cascadePriority(_ rule: (String?, any CSSSelector, [String: String])) -> Int {
    rule.1.priority
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

// Flattens the display list tree.
func treeToList(_ item: Any, into list: inout [Any]) {
    list.append(item)
    if let ve = item as? VisualEffect {
        for child in ve.children {
            treeToList(child, into: &list)
        }
    }
}

func treeToList(_ node: AccessibilityNode) -> [AccessibilityNode] {
    var result = [node]
    for child in node.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}

// Walks the layout tree and collects all paint commands into display_list.
func paintTree(_ obj: any LayoutObject, into displayList: inout [Any]) {
    if obj.shouldPaint() {
        displayList.append(contentsOf: obj.paint())
    }

    for child in obj.children {
        paintTree(child, into: &displayList)
    }
}

let REFRESH_RATE_SEC = 1.0 / 60.0

func parseTransition(_ value: String) -> [String: Int] {
    var properties: [String: Int] = [:]
    guard !value.isEmpty else { return properties }
    for item in value.split(separator: ",") {
        let parts = item.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let property = String(parts[0])
        let durationStr = String(parts[1])
        guard durationStr.hasSuffix("s"), let seconds = Double(durationStr.dropLast())
        else { continue }
        properties[property] = Int(seconds / REFRESH_RATE_SEC)
    }
    return properties
}

func diffStyles(node: DOMNode, oldStyle: [String: String], newStyle: [String: String]) -> [String:
    NumericAnimation]
{
    var animations: [String: NumericAnimation] = [:]
    let transitions = parseTransition(newStyle["transition"] ?? "")
    for (property, numFrames) in transitions {
        guard let oldVal = oldStyle[property],
            let newVal = newStyle[property],
            oldVal != newVal
        else { continue }
        if property == "opacity", let old = Double(oldVal), let new = Double(newVal) {
            animations[property] = NumericAnimation(
                oldValue: old, newValue: new, numFrames: numFrames)
        } else if property == "transform", let oldPoint = parseTransform(oldVal),
            let newPoint = parseTransform(newVal)
        {
            animations["transform-x"] = NumericAnimation(
                oldValue: Double(oldPoint.x), newValue: Double(newPoint.x), numFrames: numFrames)
            animations["transform-y"] = NumericAnimation(
                oldValue: Double(oldPoint.y), newValue: Double(newPoint.y), numFrames: numFrames)
        }
    }
    return animations
}

func parseTransform(_ value: String) -> CGPoint? {
    let pattern = #"translate\(([0-9.]+)px,\s*([0-9.]+)px\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
        let xRange = Range(match.range(at: 1), in: value),
        let yRange = Range(match.range(at: 2), in: value),
        let x = Double(value[xRange]),
        let y = Double(value[yRange])
    else { return nil }
    return CGPoint(x: x, y: y)
}

func localToAbsolute(_ obj: LayoutObject, x: CGFloat, y: CGFloat) -> CGPoint {
    var x = x
    var y = y
    var current: LayoutObject? = obj
    while let o = current {
        x += o.x
        y += o.y
        if let block = o as? BlockLayout,
            let t = parseTransform(block.node.style["transform"] ?? "")
        {
            x += t.x
            y += t.y
        }
        current = o.parent
    }
    return CGPoint(x: x, y: y)
}

func absoluteToLocal(_ obj: LayoutObject, x: CGFloat, y: CGFloat) -> CGPoint {
    var chain: [LayoutObject] = []
    var current: LayoutObject? = obj
    while let o = current {
        chain.append(o)
        current = o.parent
    }
    var x = x
    var y = y
    for o in chain.reversed() {
        x -= o.x
        y -= o.y
        if let block = o as? BlockLayout,
            let t = parseTransform(block.node.style["transform"] ?? "")
        {
            x -= t.x
            y -= t.y
        }
    }
    return CGPoint(x: x, y: y)
}

func paintVisualEffects(node: DOMNode, cmds: [any PaintCommand], rect: Rect) -> [Any] {
    let opacity = Double(node.style["opacity"] ?? "1.0") ?? 1.0
    let blendModeStr = node.style["mix-blend-mode"]
    let translation = parseTransform(node.style["transform"] ?? "")
    let radiusStr = (node.style["border-radius"] ?? "0px").replacingOccurrences(of: "px", with: "")
    let borderRadius = CGFloat(Double(radiusStr) ?? 0)

    var effectCmds: [Any] = cmds
    if borderRadius > 0 {
        let clip = Blend(
            opacity: 1.0, blendMode: .normal, node: node,
            children: [
                DrawRRect(rect: rect, parentEffect: nil, radius: borderRadius, color: .clear)
            ])
        effectCmds = [clip] + effectCmds
    }

    let blendMode: GraphicsContext.BlendMode? = {
        switch blendModeStr {
        case "multiply": return .multiply
        case "difference": return .difference
        case "destination-in": return .destinationIn
        default: return nil
        }
    }()

    let blend = Blend(opacity: opacity, blendMode: blendMode, node: node, children: effectCmds)
    let transform = Transform(translation: translation, rect: rect, node: node, children: [blend])
    return [transform]
}

func absoluteBoundsForObj(_ obj: LayoutObject) -> Rect {
    let origin = localToAbsolute(obj, x: obj.x, y: obj.y)
    return Rect(
        left: origin.x, top: origin.y, right: origin.x + obj.width, bottom: origin.y + obj.height)
}

func isFocusable(_ node: DOMNode) -> Bool {
    guard let el = node as? Element else { return false }
    return ["input", "button", "a"].contains(el.tag) || el.attributes["tabindex"] != nil
}

func getTabIndex(_ node: DOMNode) -> Int {
    guard let el = node as? Element,
        let val = el.attributes["tabindex"],
        let idx = Int(val)
    else { return 9_999_999 }
    return idx
}

func speakText(_ text: String) {
    let synthesizer = AVSpeechSynthesizer()
    let utterance = AVSpeechUtterance(string: text)
    synthesizer.speak(utterance)
}

func dpx(_ cssPx: CGFloat, zoom: CGFloat) -> CGFloat {
    return cssPx * zoom
}

func addParentPointers(_ items: [Any], parent: VisualEffect? = nil) {
    for item in items {
        if let ve = item as? VisualEffect {
            ve.parent = parent
            addParentPointers(ve.children, parent: ve)
        } else if let pc = item as? (any PaintCommand) {
            var cmd = pc
            cmd.parentEffect = parent
        }
    }
}

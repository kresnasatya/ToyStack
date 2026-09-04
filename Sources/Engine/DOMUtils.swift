import AVFoundation
import AppKit
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
struct BrowserFont {
    let ctFont: CTFont

    var ascent: CGFloat {
        CTFontGetAscent(ctFont)
    }

    var descent: CGFloat {
        CTFontGetDescent(ctFont)
    }

    var leading: CGFloat {
        CTFontGetLeading(ctFont)
    }

    var linespace: CGFloat { ascent + descent + leading }

    func measure(_ text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: ctFont]
        return (text as NSString).size(withAttributes: attrs).width
    }
}

// MARK: - Font Cache
nonisolated(unsafe) private var fontCache: [String: BrowserFont] = [:]

nonisolated(unsafe) var visitedURL: Set<String> = []

nonisolated(unsafe) var bookmarks: [String] = []

func getFont(size: Int, weight: String, style: String, family: String = "serif") -> BrowserFont {
    let key = "\(size)-\(weight)-\(style)-\(family)"
    if let cached = fontCache[key] { return cached }

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
nonisolated(unsafe) var inheritedProperties: [String: String] = [
    "font-family": "serif",
    "font-size": "16px",
    "font-style": "normal",
    "font-weight": "normal",
    "color": "black",
]

func precomputeHas(node: any DOMNode, rules: [(String?, any CSSSelector, [String: String])]) {
    let allNodes = treeToList(node)

    for n in allNodes { n.satisfiedHas = [] }

    let allHasSelectors = rules.flatMap({ $0.1.hasSelectors })
    guard !allHasSelectors.isEmpty else { return }

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
func applyStyle(
    node: any DOMNode, rules: [(String?, any CSSSelector, [String: String])],
    prefersDark: Bool = false, forcedColors: Bool = false,
    frameWidth: CGFloat = .greatestFiniteMagnitude
) {
    node.style = [:]

    for (property, defaultValue) in inheritedProperties {
        node.style[property] = node.parent?.style[property] ?? defaultValue
    }

    for (media, selector, body) in rules {
        if let m = media {
            let matches: Bool
            switch m {
            case "dark":
                matches = prefersDark
            case "light":
                matches = !prefersDark
            case "forced-colors:active":
                matches = forcedColors
            case "forced-colors:none":
                matches = !forcedColors
            default:
                if m.hasPrefix("max-width:") {
                    let limit = Double(m.dropFirst("max-width:".count)) ?? 0
                    matches = frameWidth <= CGFloat(limit)
                } else {
                    matches = false
                }
            }
            if !matches { continue }
        }
        guard selector.matches(node) else { continue }
        for (property, value) in body {
            node.style[property] = value
        }
    }

    if let element = node as? Element,
        let inlineStyle = element.attributes["style"]
    {
        for (property, value) in CSSParser(inlineStyle).body() {
            node.style[property] = value
        }
    }

    if forcedColors { forceColors(node: node) }

    if node.style["overflow"] == nil {
        if node.style["overflow-y"] == "scroll" || node.style["overflow-x"] == "scroll" {
            node.style["overflow"] = "scroll"
        }
    }

    if let fontSize = node.style["font-size"], fontSize.hasSuffix("%") {
        let parentFontSize = node.parent?.style["font-size"] ?? inheritedProperties["font-size"]!
        let percentage = Double(fontSize.dropLast()) ?? 100.0
        let parentPx = Double(parentFontSize.dropLast(2)) ?? 16.0
        node.style["font-size"] = "\(percentage / 100.0 * parentPx)px"
    }

    for child in node.children {
        applyStyle(node: child, rules: rules, prefersDark: prefersDark, forcedColors: forcedColors, frameWidth: frameWidth)
    }
}

func setInlineStyleProperty(_ elt: Element, property: String, value: String) {
    var props = CSSParser(elt.attributes["style"] ?? "").body()
    props[property.lowercased()] = value
    elt.attributes["style"] = props.map({
        "\($0.key): \($0.value)"
    })
    .joined(separator: "; ")
}

// MARK: - Cascade Priority
func cascadePriority(_ rule: (String?, any CSSSelector, [String: String])) -> Int {
    rule.1.priority
}

// MARK: - Tree Utilities
func treeToList(_ node: any DOMNode) -> [any DOMNode] {
    var result: [any DOMNode] = [node]
    for child in node.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}

func treeToList(_ obj: any LayoutObject) -> [any LayoutObject] {
    var result: [any LayoutObject] = [obj]
    for child in obj.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}

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

func paintTree(_ obj: any LayoutObject, into displayList: inout [Any]) {
    var cmds: [Any] = []

    if obj.shouldPaint() {
        cmds.append(contentsOf: obj.paint())
    }

    if let block = obj as? BlockLayout, block.node.style["overflow"] == "scroll" {
        var childCmds: [Any] = []
        let visibleTop = block.y + block.scrollOffset
        let visibleBottom = visibleTop + block.height
        var visibleChildren: [any LayoutObject] = []
        for child in obj.children {
            if child.y + child.height < visibleTop { continue }
            if child.y > visibleBottom { break }
            visibleChildren.append(child)
        }
        for child in inPaintOrder(visibleChildren) {
            paintTree(child, into: &childCmds)
        }
        let effect = ScrollEffect(
            rect: block.selfRect(), scrollOffset: block.scrollOffset, node: block.node,
            children: childCmds)
        cmds.append(effect)
        cmds.append(contentsOf: block.paintScrollbar())
    } else {
        for child in inPaintOrder(obj.children) {
            paintTree(child, into: &cmds)
        }
    }

    if let block = obj as? BlockLayout {
        cmds = paintVisualEffects(node: block.node, cmds: cmds, rect: block.selfRect())
    }

    displayList.append(contentsOf: cmds)
}

func effectiveZIndex(_ node: any DOMNode) -> Int {
    guard (node.style["position"] ?? "static") != "static" else { return 0 }
    return Int(node.style["z-index"] ?? "0") ?? 0
}

func inPaintOrder(_ children: [any LayoutObject]) -> [any LayoutObject] {
    return children.enumerated()
        .sorted { a, b in
            let za = effectiveZIndex(a.element.node)
            let zb = effectiveZIndex(b.element.node)
            return za == zb ? a.offset < b.offset : za < zb
        }
        .map { $0.element }
}

let REFRESH_RATE_SEC = 1.0 / 60.0

struct TransitionSpec {
    let numFrames: Int
    let easing: EasingFunction
}

func splitTopLevel(_ value: String, separator: Character) -> [String] {
    var parts: [String] = []
    var depth = 0
    var current = ""
    for ch in value {
        if ch == "(" {
            depth += 1
            current.append(ch)
        } else if ch == ")" {
            depth -= 1
            current.append(ch)
        } else if ch == separator && depth == 0 {
            parts.append(current)
            current = ""
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { parts.append(current) }
    return parts
}

func parseEasing(_ value: String) -> EasingFunction {
    switch value {
    case "linear": return .linear
    case "ease": return .ease
    case "ease-in": return .easeIn
    case "ease-out": return .easeOut
    default:
        if value.hasPrefix("cubic-bezier(") && value.hasSuffix(")") {
            let inner = value.dropFirst("cubic-bezier(".count).dropLast()
            let nums = inner.split(separator: ",")
                .compactMap({ Double($0.trimmingCharacters(in: .whitespaces)) })
            if nums.count == 4 {
                return .cubicBezier(x1: nums[0], y1: nums[1], x2: nums[2], y2: nums[3])
            }
        }
        return .ease
    }
}

func parseTransition(_ value: String) -> [String: TransitionSpec] {
    var properties: [String: TransitionSpec] = [:]
    guard !value.isEmpty else { return properties }
    for item in splitTopLevel(value, separator: ",") {
        let normalized = item.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let tokens = splitTopLevel(normalized, separator: " ").filter({
            !$0.isEmpty
        })
        guard tokens.count >= 2 else { continue }
        let property = tokens[0]
        let durationStr = tokens[1]
        guard durationStr.hasSuffix("s"), let seconds = Double(durationStr.dropLast())
        else { continue }
        let numFrames = Int(seconds / REFRESH_RATE_SEC)
        let easing = tokens.count >= 3 ? parseEasing(tokens[2]) : .ease
        properties[property] = TransitionSpec(numFrames: numFrames, easing: easing)
    }
    return properties
}

// MARK: - CSS animation shorthand
struct AnimationSpec {
    let name: String
    let numFrames: Int
    let infinite: Bool
    let alternate: Bool
}

func parseAnimationShorthand(_ value: String) -> AnimationSpec? {
    let tokens = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !tokens.isEmpty else { return nil }

    var name: String?
    var numFrames: Int?
    var infinite = false
    var alternate = false

    for token in tokens {
        if token.hasSuffix("s"), let seconds = Double(token.dropLast()) {
            numFrames = Int(seconds / REFRESH_RATE_SEC)
        } else if token == "infinite" {
            infinite = true
        } else if token == "alternate" {
            alternate = true
        } else {
            name = token
        }
    }

    guard let n = name, let nf = numFrames else { return nil }
    return AnimationSpec(name: n, numFrames: nf, infinite: infinite, alternate: alternate)
}

func diffStyles(node: DOMNode, oldStyle: [String: String], newStyle: [String: String]) -> [String:
    Animation]
{
    var animations: [String: Animation] = [:]
    let transitions = parseTransition(newStyle["transition"] ?? "")
    for (property, spec) in transitions {
        let numFrames = spec.numFrames
        guard let oldVal = oldStyle[property],
            let newVal = newStyle[property],
            oldVal != newVal
        else { continue }
        if property == "opacity", let old = Double(oldVal), let new = Double(newVal) {
            animations[property] = NumericAnimation(
                oldValue: old, newValue: new, numFrames: numFrames, easing: spec.easing)
            node.style[property] = oldVal
        } else if property == "transform", let oldPoint = parseTransform(oldVal),
            let newPoint = parseTransform(newVal)
        {
            animations["transform-x"] = NumericAnimation(
                oldValue: Double(oldPoint.x), newValue: Double(newPoint.x), numFrames: numFrames,
                easing: spec.easing)
            animations["transform-y"] = NumericAnimation(
                oldValue: Double(oldPoint.y), newValue: Double(newPoint.y), numFrames: numFrames,
                easing: spec.easing)
            node.style[property] = oldVal
        } else if property == "background-color",
            let old = cssColorToRGB(oldVal),
            let new = cssColorToRGB(newVal)
        {
            animations[property] = ColorAnimation(
                oldColor: old, newColor: new, numFrames: numFrames, easing: spec.easing)
            node.style[property] = oldVal
        } else if property == "width" || property == "height",
            let anim = PixelAnimation(
                oldValue: oldVal, newValue: newVal, numFrames: numFrames, easing: spec.easing)
        {
            animations[property] = anim
            node.style[property] = oldVal
        }
    }
    return animations
}

// MARK: - CSS keyframe animation construction

func buildKeyframeAnimation(
    frames: [Keyframe],
    numFrames: Int,
    infinite: Bool,
    alternate: Bool
) -> KeyframeAnimation? {
    guard let from = frames.first(where: { $0.offset == 0.0 }),
        let to = frames.first(where: { $0.offset == 1.0 })
    else { return nil }

    let differing = from.body.filter { to.body[$0.key] != $0.value }
    guard let (property, oldVal) = differing.first, let newVal = to.body[property]
    else { return nil }

    let factory: (String, String, Int, EasingFunction) -> Animation?
    switch property {
    case "opacity":
        factory = { old, new, nf, e in
            guard let o = Double(old), let n = Double(new) else { return nil }
            return NumericAnimation(oldValue: o, newValue: n, numFrames: nf, easing: e)
        }
    case "width", "height":
        factory = { old, new, nf, e in
            PixelAnimation(oldValue: old, newValue: new, numFrames: nf, easing: e)
        }
    case "background-color":
        factory = { old, new, nf, e in
            guard let o = cssColorToRGB(old), let n = cssColorToRGB(new) else { return nil }
            return ColorAnimation(oldColor: o, newColor: n, numFrames: nf, easing: e)
        }
    default:
        return nil
    }

    return KeyframeAnimation(
        animatedProperty: property, oldValue: oldVal, newValue: newVal, numFrames: numFrames,
        easing: .ease, infinite: infinite, alternate: alternate, factory: factory)
}

func parseTransform(_ value: String) -> CGPoint? {
    let pattern = #"translate\((-?[0-9.]+)px,\s*(-?[0-9.]+)px\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
        let xRange = Range(match.range(at: 1), in: value),
        let yRange = Range(match.range(at: 2), in: value),
        let x = Double(value[xRange]),
        let y = Double(value[yRange])
    else { return nil }
    return CGPoint(x: x, y: y)
}

func paintVisualEffects(node: DOMNode, cmds: [Any], rect: Rect) -> [Any] {
    let opacity = Double(node.style["opacity"] ?? "1.0") ?? 1.0
    let blendModeStr = node.style["mix-blend-mode"]
    let translation = parseTransform(node.style["transform"] ?? "")
    let radiusStr = (node.style["border-radius"] ?? "0px").replacingOccurrences(of: "px", with: "")
    let borderRadius = CGFloat(Double(radiusStr) ?? 0)
    let blurRadius = parseBlur(node.style["filter"] ?? "")

    var effectCmds: [Any] = cmds
    if borderRadius > 0 {
        let clip = Blend(
            opacity: 1.0, blendMode: .normal, node: node,
            children: [
                DrawRRect(rect: rect, parentEffect: nil, radius: borderRadius, color: "transparent")
            ])
        effectCmds = [clip] + effectCmds
    }

    if blurRadius > 0 {
        effectCmds = [BlurFilter(radius: blurRadius, node: node, children: effectCmds)]
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

// MARK: - CSS outline
func cssOutline(_ node: any DOMNode, rect: Rect) -> DrawOutline? {
    let style = node.style["outline-style"] ?? "none"
    guard style != "none", style != "hidden" else { return nil }
    guard let thickness = outlineWidthPx(node.style["outline-width"] ?? "medium"),
        thickness > 0
    else { return nil }
    let color = node.style["outline-color"] ?? node.style["color"] ?? "black"
    return DrawOutline(rect: rect, color: color, thickness: thickness)
}

private func outlineWidthPx(_ token: String) -> CGFloat? {
    switch token {
        case "thin": return 1
        case "medium": return 3
        case "thick": return 5
        default:
            guard token.hasSuffix("px"), let value = Double(token.dropLast(2)) else { return nil }
            return CGFloat(value)
    }
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

func computeZoom(_ node: any DOMNode, parentZoom: CGFloat) -> CGFloat {
    guard let zoomStr = node.style["zoom"] else { return parentZoom }
    let trimmed = zoomStr.trimmingCharacters(in: .whitespaces)
    let factor: CGFloat
    if trimmed.hasSuffix("%"), let pct = Double(trimmed.dropLast()) {
        factor = CGFloat(pct / 100.0)
    } else if let val = Double(trimmed) {
        factor = CGFloat(val)
    } else {
        return parentZoom
    }
    return parentZoom * factor
}

func dpx(_ cssPx: CGFloat, zoom: CGFloat) -> CGFloat {
    return cssPx * zoom
}

func addParentPointers(_ items: inout [Any], parent: VisualEffect? = nil) {
    var visited = Set<ObjectIdentifier>()
    var stack: [([Any], VisualEffect?)] = [(items, parent)]

    while !stack.isEmpty {
        let (currentNodes, currentParent) = stack.removeLast()
        for node in currentNodes {
            if let ve = node as? VisualEffect {
                let id = ObjectIdentifier(ve)
                guard !visited.contains(id) else { continue }
                visited.insert(id)
                ve.parent = currentParent
                for i in 0..<ve.children.count {
                    if var pc = ve.children[i] as? (any PaintCommand) {
                        pc.parentEffect = ve
                        ve.children[i] = pc
                    }
                }
                stack.append((ve.children, ve))
            }
        }
    }
}

func parseBlur(_ value: String) -> CGFloat {
    guard value.hasPrefix("blur("), value.hasSuffix(")") else { return 0 }
    let inner = value.dropFirst(5).dropLast()
    let digits = inner.hasSuffix("px") ? inner.dropLast(2) : inner
    return CGFloat(Double(digits) ?? 0)
}

import Foundation

// MARK: - CSSParseError
enum CSSParseError: Error {
    case parseError
}

// MARK: - Keyframe
struct Keyframe {
    let offset: Double
    let body: [String: String]
}

// MARK: - CSSParser
class CSSParser {
    private let chars: [Character]
    private let origin: CascadeOrigin
    private var i: Int = 0
    private static let borderStyleKeywords: Set<String> = [
        "none", "hidden", "solid", "dashed", "dotted",
        "double", "groove", "ridge", "inset", "outset",
    ]
    private static let borderWidthKeywords: Set<String> = ["thin", "medium", "thick"]
    private static let screenMediaTypes: Set<String> = ["all", "screen"]

    init(_ s: String, origin: CascadeOrigin = .author) {
        self.chars = Array(s)
        self.origin = origin
    }

    // Normal author rules stay bare; every other origin and importance level
    // is ranked relative to them.
    private func ruleSelector(_ selector: any CSSSelector, isImportant: Bool) -> any CSSSelector {
        if origin == .author, !isImportant { return selector }
        return OriginSelector(base: selector, origin: origin, isImportant: isImportant)
    }

    private func skipWhitespace() {
        while i < chars.count {
            if chars[i].isWhitespace {
                i += 1
            } else if i + 1 < chars.count && chars[i] == "/" && chars[i + 1] == "*" {
                i += 2
                while i < chars.count {
                    if i + 1 < chars.count && chars[i] == "*" && chars[i + 1] == "/" {
                        i += 2
                        break
                    }
                    i += 1
                }
            } else {
                break
            }
        }
    }

    private func word() throws -> String {
        let start: Int = i
        while i < chars.count {
            let c: Character = chars[i]
            if c.isLetter || c.isNumber || "#-.%".contains(c) {
                i += 1
            } else {
                break
            }
        }
        guard i > start else {
            throw CSSParseError.parseError
        }
        return String(chars[start..<i])
    }

    private func literal(_ c: Character) throws {
        guard i < chars.count && chars[i] == c else {
            throw CSSParseError.parseError
        }
        i += 1
    }

    private func ignoreUntil(_ targets: Set<Character>) -> Character? {
        while i < chars.count {
            if targets.contains(chars[i]) {
                return chars[i]
            }
            i += 1
        }
        return nil
    }

    private func pair() throws -> (String, String) {
        skipWhitespace()
        let prop: String = try word()
        skipWhitespace()
        try literal(":")
        skipWhitespace()
        var val: String = try word()
        if i < chars.count && chars[i] == "(" {
            val += consumeParentheses()
        }
        if prop.lowercased() == "aspect-ratio" {
            val = aspectRatioValue(val)
        }
        return (prop.lowercased(), val)
    }

    private func aspectRatioValue(_ first: String) -> String {
        var tokens: [String] = [first]
        skipWhitespace()
        while i < chars.count && chars[i] != ";" && chars[i] != "}" {
            if chars[i] == "/" {
                tokens.append("/")
                i += 1
                skipWhitespace()
                continue
            }
            guard let token = try? word() else { break }
            tokens.append(token)
            skipWhitespace()
        }
        return tokens.joined(separator: " ")
    }

    private func consumeParentheses() -> String {
        let start: Int = i
        var depth: Int = 0
        while i < chars.count {
            if chars[i] == "(" {
                depth += 1
                i += 1
            } else if chars[i] == ")" {
                depth -= 1
                i += 1
                if depth == 0 { break }
            } else {
                i += 1
            }
        }
        return String(chars[start..<i])
    }

    private static let boxSides: [String] = ["top", "right", "bottom", "left"]

    private static func expand(shorthand: String, tokens: [String]) -> [String: String]? {
        switch shorthand {
        case "font": return expandFont(tokens)
        case "background": return expandBackground(tokens)
        case "border": return expandBorder(tokens, into: boxSides.map({ "border-\($0)" }))
        case "border-top", "border-right", "border-bottom", "border-left":
            return expandBorder(tokens, into: [shorthand])
        case "border-width": return expandBox(tokens, prefix: "border", suffix: "-width")
        case "border-style": return expandBox(tokens, prefix: "border", suffix: "-style")
        case "border-color": return expandBox(tokens, prefix: "border", suffix: "-color")
        case "outline": return expandBorder(tokens, into: ["outline"])
        case "margin": return expandBox(tokens, prefix: "margin", suffix: "")
        case "padding": return expandBox(tokens, prefix: "padding", suffix: "")
        default: return nil
        }
    }

    private static func expandFont(_ tokens: [String]) -> [String: String] {
        var props: [String: String] = [:]
        var t: [String] = tokens
        if let f = t.first, f == "italic" || f == "oblique" {
            props["font-style"] = t.removeFirst()
        }
        if let f = t.first, f == "bold" {
            props["font-weight"] = t.removeFirst()
        }
        if let f = t.first, f.hasSuffix("px") || f.hasSuffix("%") || f.hasSuffix("em") {
            props["font-size"] = t.removeFirst()
        }
        if !t.isEmpty {
            props["font-family"] = t.joined(separator: " ")
        }
        return props
    }

    private static func expandBackground(_ tokens: [String]) -> [String: String] {
        var props: [String: String] = [:]
        for token in tokens where token != "," {
            if token.lowercased().hasPrefix("url(") {
                props["background-image"] = token
            } else if cssColorToRGB(token) != nil {
                props["background-color"] = token
            }
        }
        return props
    }

    private static func expandBorder(_ tokens: [String], into prefixes: [String]) -> [String: String] {
        var part: [String: String] = [:]
        for token in tokens {
            if token.hasSuffix("px") || token.hasSuffix("em") || borderWidthKeywords.contains(token)
            {
                part["width"] = token
            } else if borderStyleKeywords.contains(token) {
                part["style"] = token
            } else {
                part["color"] = token
            }
        }
        var props: [String: String] = [:]
        for prefix in prefixes {
            for (name, value) in part {
                props["\(prefix)-\(name)"] = value
            }
        }
        return props
    }

    /// CSS Backgrounds 3 §3.3: a missing bottom copies top, and a missing
    /// left copies right. Margin and padding spread the same way.
    private static func expandBox(_ tokens: [String], prefix: String, suffix: String) -> [String: String] {
        let top: String = tokens[0]
        let right: String = tokens.count > 1 ? tokens[1] : top
        let bottom: String = tokens.count > 2 ? tokens[2] : top
        let left: String = tokens.count > 3 ? tokens[3] : right
        var props: [String: String] = [:]
        for (side, value) in zip(boxSides, [top, right, bottom, left]) {
            props["\(prefix)-\(side)\(suffix)"] = value
        }
        return props
    }

    private static let shorthands: Set<String> = [
        "font", "border", "outline", "margin", "padding", "background", "transition", "animation",
        "border-top", "border-right", "border-bottom", "border-left",
        "border-width", "border-style", "border-color",
    ]

    private static func isShortHand(_ prop: String) -> Bool {
        return shorthands.contains(prop)
    }

    private func bodyParts() -> (normal: [String: String], important: [String: String]) {
        var normal: [String: String] = [:]
        var important: [String: String] = [:]

        while i < chars.count && chars[i] != "}" {
            if let (prop, val) = try? pair() {
                var tokens: [String] = [val]
                if CSSParser.isShortHand(prop) {
                    skipWhitespace()
                    while i < chars.count && chars[i] != ";" && chars[i] != "}" {
                        if chars[i] == "," {
                            tokens.append(",")
                            i += 1
                            skipWhitespace()
                            continue
                        }
                        guard var t = try? word() else { break }
                        if i < chars.count && chars[i] == "(" {
                            t += consumeParentheses()
                        }
                        tokens.append(t)
                        skipWhitespace()
                    }
                }

                skipWhitespace()
                var isImportant: Bool = false
                if i < chars.count && chars[i] == "!" {
                    i += 1
                    if let keyword = try? word(), keyword.lowercased() == "important" {
                        isImportant = true
                    }
                }

                if let expanded = CSSParser.expand(shorthand: prop, tokens: tokens) {
                    for (k, v) in expanded {
                        isImportant ? (important[k] = v) : (normal[k] = v)
                    }
                } else {
                    let fullVal: String = tokens.joined(separator: " ")
                    isImportant ? (important[prop] = fullVal) : (normal[prop] = fullVal)
                }
                skipWhitespace()
                _ = try? literal(";")
                skipWhitespace()
            } else {
                let found: Character? = ignoreUntil([";", "}"])
                if found == ";" {
                    _ = try? literal(";")
                    skipWhitespace()
                } else {
                    break
                }
            }
        }
        return (normal, important)
    }

    func body() -> [String: String] {
        let parts: (normal: [String : String], important: [String : String]) = bodyParts()
        return parts.normal.merging(parts.important) { _, imp in imp }
    }

    // CSS Syntax §4.3.8: a backslash starts an escape unless a newline follows it.
    private func startsEscape(at index: Int) -> Bool {
        return index + 1 < chars.count && chars[index] == "\\" && !chars[index + 1].isNewline
    }

    // CSS Syntax §4.3.7: up to six hex digits name a code point and one whitespace after
    // them ends the escape; any other character after the backslash stands for itself.
    private func escapedCharacter() -> Character {
        i += 1
        var hex: String = ""
        while i < chars.count, hex.count < 6, chars[i].isHexDigit {
            hex.append(chars[i])
            i += 1
        }
        guard !hex.isEmpty else {
            let literal: Character = chars[i]
            i += 1
            return literal
        }
        if i < chars.count, chars[i].isWhitespace { i += 1 }
        guard let value: UInt32 = UInt32(hex, radix: 16), value != 0,
            let scalar: Unicode.Scalar = Unicode.Scalar(value)
        else { return "\u{FFFD}" }
        return Character(scalar)
    }

    // CSS Syntax §4.3.12: an ident is letters, digits, "-", "_", any non-ASCII
    // character, and escapes. Tailwind relies on escapes for names like "md:hidden".
    private func identifier() -> String? {
        var result: String = ""
        while i < chars.count {
            let c: Character = chars[i]
            if c.isLetter || c.isNumber || c == "-" || c == "_" || !c.isASCII {
                result.append(c)
                i += 1
            } else if startsEscape(at: i) {
                result.append(escapedCharacter())
            } else {
                break
            }
        }
        return result.isEmpty ? nil : result
    }

    private func attributeSelector() -> (any CSSSelector)? {
        i += 1
        skipWhitespace()
        guard let name = try? word() else { return nil }
        skipWhitespace()

        var value: String? = nil
        if i < chars.count && chars[i] == "=" {
            i += 1
            skipWhitespace()
            guard let v = quotedOrWord() else { return nil }
            value = v
            skipWhitespace()
        }

        guard (try? literal("]")) != nil else { return nil }
        return AttributeSelector(attribute: name.lowercased(), value: value)
    }

    private func quotedOrWord() -> String? {
        guard i < chars.count else { return nil }
        let quote: Character = chars[i]
        guard quote == "\"" || quote == "'" else { return try? word() }
        i += 1
        let start: Int = i
        while i < chars.count && chars[i] != quote { i += 1 }
        guard i < chars.count else { return nil }
        let text: String = String(chars[start..<i])
        i += 1
        return text
    }

    private func parseCompoundSelector() -> (any CSSSelector)? {
        var parts: [any CSSSelector] = []

        if i < chars.count && chars[i] == "*" {
            i += 1
            parts.append(UniversalSelector())
        } else if let tag = identifier() {
            parts.append(TagSelector(tag: tag.lowercased()))
        }

        while i < chars.count && (chars[i] == "." || chars[i] == "#" || chars[i] == "[") {
            let marker: Character = chars[i]
            if marker == "[" {
                guard let attr = attributeSelector() else { return TagSelector(tag: "") }
                parts.append(attr)
                continue
            }
            i += 1
            guard let name = identifier() else { return TagSelector(tag: "") }
            parts.append(marker == "." ? ClassSelector(cls: name) : IDSelector(id: name))
        }

        while i < chars.count && chars[i] == ":" {
            i += 1
            guard let keyword = try? word() else { break }
            if keyword == "has" {
                guard (try? literal("(")) != nil else { break }
                skipWhitespace()
                let inner: any CSSSelector = selector()
                skipWhitespace()
                _ = try? literal(")")
                parts.append(HasSelector(inner: inner))
            } else if keyword == "is" || keyword == "where" {
                guard (try? literal("(")) != nil else { return TagSelector(tag: "") }
                skipWhitespace()
                guard let list = try? selectorList(), (try? literal(")")) != nil else {
                    return TagSelector(tag: "")
                }
                parts.append(IsSelector(alternatives: list, keepsSpecificity: keyword == "is"))
            } else {
                let base: any CSSSelector =
                    parts.isEmpty
                    ? TagSelector(tag: "")
                    : (parts.count == 1 ? parts[0] : SelectorSequence(selectors: parts))
                parts = [PseudoclassSelector(pseudoclass: keyword.lowercased(), base: base)]
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.count == 1 ? parts[0] : SelectorSequence(selectors: parts)
    }

    func selector() -> any CSSSelector {
        guard let first = parseCompoundSelector() else {
            return TagSelector(tag: "")
        }

        var parts: [any CSSSelector] = [first]
        skipWhitespace()
        while i < chars.count && chars[i] != "{" && chars[i] != ")" {
            guard let compound = parseCompoundSelector() else { break }
            parts.append(compound)
            skipWhitespace()
        }

        return parts.count == 1 ? parts[0] : DescendantSelector(selectors: parts)
    }

    private func selectorList() throws -> [any CSSSelector] {
        var selectors: [any CSSSelector] = [selector()]
        skipWhitespace()
        while i < chars.count && chars[i] == "," {
            i += 1
            skipWhitespace()
            guard i < chars.count, chars[i] != "{", chars[i] != "}", chars[i] != "," else {
                throw CSSParseError.parseError
            }
            selectors.append(selector())
            skipWhitespace()
        }
        return selectors
    }

    private func mediaQuery() throws -> String {
        try literal("@")
        skipWhitespace()
        guard (try? word()) == "media" else { throw CSSParseError.parseError }
        skipWhitespace()
        if i < chars.count && chars[i] == "(" {
            return try mediaFeature()
        }
        var mediaType: String = try word().lowercased()
        if mediaType == "only" {
            skipWhitespace()
            mediaType = try word().lowercased()
        }
        // ToyStack only draws to a screen, so a print or speech block can never
        // apply; dropping it like a parse error gives the same result.
        guard CSSParser.screenMediaTypes.contains(mediaType) else { throw CSSParseError.parseError }
        skipWhitespace()
        if i < chars.count && chars[i] == "{" {
            return MediaFeatures.anyScreen
        }
        guard try word().lowercased() == "and" else { throw CSSParseError.parseError }
        skipWhitespace()
        return try mediaFeature()
    }

    private func mediaFeature() throws -> String {
        try literal("(")
        skipWhitespace()
        let prop: String = try word()
        skipWhitespace()
        try literal(":")
        skipWhitespace()
        let val: String = try word()
        skipWhitespace()
        try literal(")")
        switch prop {
            case "prefers-color-scheme":
                return val
            case "max-width", "min-width", "width":
                guard val.hasSuffix("px"), let px = Double(val.dropLast(2)) else {
                    throw CSSParseError.parseError
                }
                return "\(prop):\(px)"
            case "forced-colors":
                guard val == "active" || val == "none" else {
                    throw CSSParseError.parseError
                }
                return "forced-colors:\(val)"
            default:
                throw CSSParseError.parseError
        }
    }

    private func parseKeyframeOffset() throws -> Double {
        skipWhitespace()
        let w: String = try word()
        switch w.lowercased() {
        case "from": return 0.0
        case "to": return 1.0
        default:
            guard w.hasSuffix("%"), let pct = Double(w.dropLast()) else {
                throw CSSParseError.parseError
            }
            return pct / 100.0
        }
    }

    private func skipBlock() {
        var depth: Int = 1
        while i < chars.count {
            if chars[i] == "{" {
                depth += 1
            } else if chars[i] == "}" {
                depth -= 1
                if depth == 0 {
                    i += 1
                    return
                }
            }
            i += 1
        }
    }

    func parse() -> (
        rules: [(String?, any CSSSelector, [String: String])], keyframes: [String: [Keyframe]]
    ) {
        var rules: [(String?, any CSSSelector, [String: String])] = []
        var keyframes: [String: [Keyframe]] = [:]
        var media: String? = nil
        while i < chars.count {
            skipWhitespace()
            do {
                if i < chars.count && chars[i] == "@" && media == nil {
                    let saveI: Int = i
                    i += 1
                    skipWhitespace()
                    let keyword: String = (try? word()) ?? ""
                    if keyword == "media" {
                        i = saveI
                        media = try mediaQuery()
                        skipWhitespace()
                        do {
                            try literal("{")
                        } catch {
                            media = nil
                            throw error
                        }
                        skipWhitespace()
                    } else if keyword == "keyframes" {
                        skipWhitespace()
                        let name: String = try word()
                        skipWhitespace()
                        try literal("{")
                        var frames: [Keyframe] = []
                        while i < chars.count && chars[i] != "}" {
                            let offset: Double = try parseKeyframeOffset()
                            skipWhitespace()
                            try literal("{")
                            skipWhitespace()
                            let parts: (normal: [String : String], important: [String : String]) = bodyParts()
                            try literal("}")
                            skipWhitespace()
                            frames.append(Keyframe(offset: offset, body: parts.normal))
                        }
                        try literal("}")
                        skipWhitespace()
                        keyframes[name] = frames
                    } else {
                        i = saveI
                        throw CSSParseError.parseError
                    }
                } else if i < chars.count && chars[i] == "}" && media != nil {
                    try literal("}")
                    media = nil
                    skipWhitespace()
                } else {
                    let selectors: [any CSSSelector] = try selectorList()
                    try literal("{")
                    skipWhitespace()
                    let parts: (normal: [String : String], important: [String : String]) = bodyParts()
                    try literal("}")
                    skipWhitespace()
                    for sel in selectors {
                        if !parts.normal.isEmpty {
                            rules.append((media, ruleSelector(sel, isImportant: false), parts.normal))
                        }
                        if !parts.important.isEmpty {
                            rules.append((media, ruleSelector(sel, isImportant: true), parts.important))
                        }
                    }
                }
            } catch {
                let found: Character? = ignoreUntil(["{", "}"])
                if found == "{" {
                    _ = try? literal("{")
                    skipBlock()
                    skipWhitespace()
                } else if found == "}" {
                    _ = try? literal("}")
                    skipWhitespace()
                } else {
                    break
                }
            }
        }
        return (rules, keyframes)
    }
}

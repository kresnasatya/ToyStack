import Foundation

// MARK: - CSSSelector
protocol CSSSelector: Sendable {
    var priority: Int { get }
    var hasSelectors: [HasSelector] { get }
    func matches(_ node: any DOMNode) -> Bool
}

// MARK: - TagSelector
struct TagSelector: CSSSelector {
    let tag: String
    let priority: Int = 1
    var hasSelectors: [HasSelector] { [] }

    func matches(_ node: any DOMNode) -> Bool {
        guard let element = node as? Element else {
            return false
        }
        return element.tag == tag
    }
}

// MARK: - UniversalSelector
struct UniversalSelector: CSSSelector {
    let priority: Int = 0
    var hasSelectors: [HasSelector] { [] }

    func matches(_ node: any DOMNode) -> Bool {
        node is Element
    }
}

// MARK: - IDSelector
struct IDSelector: CSSSelector {
    let id: String
    let priority: Int = 100
    var hasSelectors: [HasSelector] { [] }

    func matches(_ node: any DOMNode) -> Bool {
        guard let element = node as? Element else { return false }
        return element.attributes["id"] == id
    }
}

// MARK: - ClassSelector
struct ClassSelector: CSSSelector {
    let cls: String
    let priority: Int = 10
    var hasSelectors: [HasSelector] { [] }

    func matches(_ node: any DOMNode) -> Bool {
        guard let element = node as? Element else { return false }
        let classes = element.attributes["class"]?.split(separator: " ").map(String.init) ?? []
        return classes.contains(cls)
    }
}

// MARK: - AttributeSelector
struct AttributeSelector: CSSSelector {
    let attribute: String
    let value: String?
    let priority: Int = 10
    var hasSelectors: [HasSelector] { [] }

    func matches(_ node: any DOMNode) -> Bool {
        guard let element = node as? Element,
            let actual = element.attributes[attribute]
        else { return false }
        guard let value = value else { return true }
        return actual == value
    }
}

// MARK: - SelectorSequence
struct SelectorSequence: CSSSelector {
    let selectors: [any CSSSelector]
    var priority: Int { selectors.reduce(0, { $0 + $1.priority }) }
    var hasSelectors: [HasSelector] { selectors.flatMap { $0.hasSelectors } }

    func matches(_ node: any DOMNode) -> Bool {
        selectors.allSatisfy({ $0.matches(node) })
    }
}

// MARK: - DescendantSelector
struct DescendantSelector: CSSSelector {
    let selectors: [any CSSSelector]
    var priority: Int { selectors.reduce(0, { $0 + $1.priority }) }
    var hasSelectors: [HasSelector] { selectors.flatMap { $0.hasSelectors } }

    func matches(_ node: any DOMNode) -> Bool {
        guard selectors.last!.matches(node) else { return false }

        var j = selectors.count - 2
        var current = node.parent
        while let p = current {
            if j < 0 { return true }
            if selectors[j].matches(p) { j -= 1 }
            current = p.parent
        }
        return j < 0
    }
}

// MARK: - ImportantSelector
struct ImportantSelector: CSSSelector {
    let base: any CSSSelector
    var priority: Int { base.priority + 10_000 }
    var hasSelectors: [HasSelector] { base.hasSelectors }

    func matches(_ node: any DOMNode) -> Bool {
        base.matches(node)
    }
}

// MARK: - HasSelector
struct HasSelector: CSSSelector {
    nonisolated(unsafe) private static var counter: Int = 0
    let id: Int
    let inner: any CSSSelector
    var priority: Int { inner.priority }
    var hasSelectors: [HasSelector] { [self] }

    init(inner: any CSSSelector) {
        self.id = HasSelector.counter
        HasSelector.counter += 1
        self.inner = inner
    }

    func matches(_ node: any DOMNode) -> Bool {
        node.satisfiedHas.contains(id)
    }
}

// MARK: - PseudoclassSelector
struct PseudoclassSelector: CSSSelector {
    let pseudoclass: String
    let base: any CSSSelector
    var priority: Int { base.priority }
    var hasSelectors: [HasSelector] { base.hasSelectors }

    func matches(_ node: any DOMNode) -> Bool {
        guard base.matches(node) else { return false }
        switch pseudoclass {
        case "focus": return node.isFocused
        case "focus-visible": return node.isFocusVisible
        default: return false
        }
    }
}

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
    private var i: Int = 0
    private static let borderStyleKeywords: Set<String> = [
        "none", "hidden", "solid", "dashed", "dotted",
        "double", "groove", "ridge", "inset", "outset",
    ]
    private static let borderWidthKeywords: Set<String> = ["thin", "medium", "thick"]

    init(_ s: String) {
        self.chars = Array(s)
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
        let start = i
        while i < chars.count {
            let c = chars[i]
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
        let prop = try word()
        skipWhitespace()
        try literal(":")
        skipWhitespace()
        var val = try word()
        if i < chars.count && chars[i] == "(" {
            let start = i
            var depth = 0
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
            val += String(chars[start..<i])
        }
        return (prop.lowercased(), val)
    }

    private static func expand(shorthand: String, tokens: [String]) -> [String: String]? {
        switch shorthand {
        case "font": return expandFont(tokens)
        case "background": return expandBackground(tokens)
        case "border": return expandBorder(tokens, prefix: "border")
        case "outline": return expandBorder(tokens, prefix: "outline")
        case "margin": return expandBox(tokens, prefix: "margin")
        case "padding": return expandBox(tokens, prefix: "padding")
        default: return nil
        }
    }

    private static func expandFont(_ tokens: [String]) -> [String: String] {
        var props: [String: String] = [:]
        var t = tokens
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
            if cssColorToRGB(token) != nil {
                props["background-color"] = token
            }
        }
        return props
    }

    private static func expandBorder(_ tokens: [String], prefix: String) -> [String: String] {
        var props: [String: String] = [:]
        for token in tokens {
            if token.hasSuffix("px") || token.hasSuffix("em") || borderWidthKeywords.contains(token)
            {
                props["\(prefix)-width"] = token
            } else if borderStyleKeywords.contains(token) {
                props["\(prefix)-style"] = token
            } else {
                props["\(prefix)-color"] = token
            }
        }
        return props
    }

    private static func expandBox(_ tokens: [String], prefix: String) -> [String: String] {
        var props: [String: String] = [:]
        switch tokens.count {
        case 1:
            props["\(prefix)-top"] = tokens[0]
            props["\(prefix)-right"] = tokens[0]
            props["\(prefix)-bottom"] = tokens[0]
            props["\(prefix)-left"] = tokens[0]
        case 2:
            props["\(prefix)-top"] = tokens[0]
            props["\(prefix)-right"] = tokens[1]
            props["\(prefix)-bottom"] = tokens[0]
            props["\(prefix)-left"] = tokens[1]
        case 3:
            props["\(prefix)-top"] = tokens[0]
            props["\(prefix)-right"] = tokens[1]
            props["\(prefix)-bottom"] = tokens[2]
            props["\(prefix)-left"] = tokens[1]
        default:
            props["\(prefix)-top"] = tokens[0]
            props["\(prefix)-right"] = tokens[1]
            props["\(prefix)-bottom"] = tokens[2]
            props["\(prefix)-left"] = tokens[3]
        }
        return props
    }

    private static func isShortHand(_ prop: String) -> Bool {
        ["font", "border", "outline", "margin", "padding", "background", "transition", "animation"].contains(prop)
    }

    private func bodyParts() -> (normal: [String: String], important: [String: String]) {
        var normal: [String: String] = [:]
        var important: [String: String] = [:]

        while i < chars.count && chars[i] != "}" {
            if let (prop, val) = try? pair() {
                var tokens = [val]
                if CSSParser.isShortHand(prop) {
                    skipWhitespace()
                    while i < chars.count && chars[i] != ";" && chars[i] != "}" {
                        if chars[i] == "," {
                            tokens.append(",")
                            i += 1
                            skipWhitespace()
                            continue
                        }
                        guard let t = try? word() else { break }
                        tokens.append(t)
                        skipWhitespace()
                    }
                }

                skipWhitespace()
                var isImportant = false
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
                    let fullVal = tokens.joined(separator: " ")
                    isImportant ? (important[prop] = fullVal) : (normal[prop] = fullVal)
                }
                skipWhitespace()
                _ = try? literal(";")
                skipWhitespace()
            } else {
                let found = ignoreUntil([";", "}"])
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
        let parts = bodyParts()
        return parts.normal.merging(parts.important) { _, imp in imp }
    }

    private func parseSimpleSelector(_ token: String) -> any CSSSelector {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var selectors: [any CSSSelector] = []
        if let first = parts.first {
            let hashParts = first.split(separator: "#", omittingEmptySubsequences: false).map(
                String.init)
            if let tag = hashParts.first, !tag.isEmpty {
                selectors.append(TagSelector(tag: tag.lowercased()))
            }
            if hashParts.count > 1, let id = hashParts.last, !id.isEmpty {
                selectors.append(IDSelector(id: id))
            }
        }
        for cls in parts.dropFirst() where !cls.isEmpty {
            selectors.append(ClassSelector(cls: cls))
        }
        guard !selectors.isEmpty else { return TagSelector(tag: "") }
        return selectors.count == 1 ? selectors[0] : SelectorSequence(selectors: selectors)
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
        let quote = chars[i]
        guard quote == "\"" || quote == "'" else { return try? word() }
        i += 1
        let start = i
        while i < chars.count && chars[i] != quote { i += 1 }
        guard i < chars.count else { return nil }
        let text = String(chars[start..<i])
        i += 1
        return text
    }

    private func parseCompoundSelector() -> (any CSSSelector)? {
        var parts: [any CSSSelector] = []

        if i < chars.count && chars[i] == "*" {
            i += 1
            parts.append(UniversalSelector())
        } else if let w = try? word() {
            parts.append(parseSimpleSelector(w))
        }

        while i < chars.count && chars[i] == "[" {
            guard let attr = attributeSelector() else {
                return TagSelector(tag: "")
            }
            parts.append(attr)
        }

        while i < chars.count && chars[i] == ":" {
            i += 1
            guard let keyword = try? word() else { break }
            if keyword == "has" {
                guard (try? literal("(")) != nil else { break }
                skipWhitespace()
                let inner = selector()
                skipWhitespace()
                _ = try? literal(")")
                parts.append(HasSelector(inner: inner))
            } else {
                let base =
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

    private func mediaQuery() throws -> String {
        try literal("@")
        skipWhitespace()
        guard (try? word()) == "media" else { throw CSSParseError.parseError }
        skipWhitespace()
        try literal("(")
        skipWhitespace()
        let prop = try word()
        skipWhitespace()
        try literal(":")
        skipWhitespace()
        let val = try word()
        skipWhitespace()
        try literal(")")
        switch prop {
            case "prefers-color-scheme":
                return val
            case "max-width":
                guard val.hasSuffix("px"), let px = Double(val.dropLast(2)) else {
                    throw CSSParseError.parseError
                }
                return "max-width:\(px)"
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
        let w = try word()
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
        var depth = 1
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
                    let saveI = i
                    i += 1
                    skipWhitespace()
                    let keyword = (try? word()) ?? ""
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
                        let name = try word()
                        skipWhitespace()
                        try literal("{")
                        var frames: [Keyframe] = []
                        while i < chars.count && chars[i] != "}" {
                            let offset = try parseKeyframeOffset()
                            skipWhitespace()
                            try literal("{")
                            skipWhitespace()
                            let parts = bodyParts()
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
                    let sel = selector()
                    try literal("{")
                    skipWhitespace()
                    let parts = bodyParts()
                    try literal("}")
                    skipWhitespace()
                    if !parts.normal.isEmpty {
                        rules.append((media, sel, parts.normal))
                    }
                    if !parts.important.isEmpty {
                        rules.append((media, ImportantSelector(base: sel), parts.important))
                    }
                }
            } catch {
                let found = ignoreUntil(["{", "}"])
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

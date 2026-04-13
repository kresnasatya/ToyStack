import Foundation

// MARK: - CSSSelector Protocol
// Any selector can test whether it matches a DOM node and report it's priority.
// Higher priority wins when two rules set the same property.
protocol CSSSelector: Sendable {
    var priority: Int { get }
    var hasSelectors: [HasSelector] { get }
    func matches(_ node: any DOMNode) -> Bool
}

// MARK: - TagSelector
// Matches Element nodes whose tag equals self.tag
// Example: TagSelector("p") matches every <p> element.
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
// Matches Element nodes that have given class in their class attribute.
// Example: ClassSelector("links") matches <nav class="links">.
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

// MARK: - SelectorSequence
// Matches when ALL selectors in the sequence match the same node.
// Example: SelectorSequence([TagSelector("span"), ClassSelector("announce")])
//          matches <span class="announce">
struct SelectorSequence: CSSSelector {
    let selectors: [any CSSSelector]
    var priority: Int { selectors.reduce(0, { $0 + $1.priority }) }
    var hasSelectors: [HasSelector] { selectors.flatMap { $0.hasSelectors } }

    func matches(_ node: any DOMNode) -> Bool {
        selectors.allSatisfy({ $0.matches(node) })
    }
}

// MARK: - DescendantSelector
// Matches a node when its ancestors satisfy all selectors left-to-right.
// Stores a flat list instead of nested pairs for 0(n+d) matching.
// Example: ["div", "p", "span"] matches <span> inside <p> inside <div>.
struct DescendantSelector: CSSSelector {
    let selectors: [any CSSSelector]  // left-to-right: [most-ancestral, ..., node]
    var priority: Int { selectors.reduce(0, { $0 + $1.priority }) }
    var hasSelectors: [HasSelector] { selectors.flatMap { $0.hasSelectors } }

    func matches(_ node: any DOMNode) -> Bool {
        // The node itself must match the rightmost selector.
        guard selectors.last!.matches(node) else { return false }

        // Single walk up the ancestor chain, consuming selectors right-to-left.
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
// Wraps any selector and adds 10_000 to priority, implementing !important.
// The base selector still controls which nodes match; only priority changes.
struct ImportantSelector: CSSSelector {
    let base: any CSSSelector
    var priority: Int { base.priority + 10_000 }
    var hasSelectors: [HasSelector] { base.hasSelectors }

    func matches(_ node: any DOMNode) -> Bool {
        base.matches(node)
    }
}

// MARK: - HasSelector
// Matches a node if any of its descendants matches the inner selector.
// Example: HasSelector(TagSelector("p")) matches any element containing a <p>.
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

    // O(1) - reads the precomputed result set on the node
    func matches(_ node: any DOMNode) -> Bool {
        node.satisfiedHas.contains(id)
    }
}

// MARK: - PseudoclassSelector
// Matches when the base selector matches AND the pseudo-class condition holds.
// Example: PseudoClassSelector("focus", TagSelector("input")) matches focused <input>.
struct PseudoclassSelector: CSSSelector {
    let pseudoclass: String
    let base: any CSSSelector
    var priority: Int { base.priority }
    var hasSelectors: [HasSelector] { base.hasSelectors }

    func matches(_ node: any DOMNode) -> Bool {
        guard base.matches(node) else { return false }
        switch pseudoclass {
        case "focus": return node.isFocused
        default: return false
        }
    }
}

// MARK: - CSSParseError
enum CSSParseError: Error {
    case parseError
}

// MARK: - CSSParser
// Parses CSS text into [(selector, properties)] pairs.
// Uses a [Character] array for efficient 0(1) character access.
class CSSParser {
    // Swift String indexing is not integer-based, so convert to [Character].
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

    // --- Low-level helpers ---

    // Advances past all whitespace characters (spaces, newlines, tabs).
    private func skipWhitespace() {
        while i < chars.count && chars[i].isWhitespace {
            i += 1
        }
    }

    // Reads token of word characters: letters, digits, and # - . %
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

    // Asserts the next character equals `c` and consumes it.
    private func literal(_ c: Character) throws {
        guard i < chars.count && chars[i] == c else {
            throw CSSParseError.parseError
        }
        i += 1
    }

    // Error recovery: advances until one of the target characters is found.
    // Returns the found character, or nil if the end of input was reached.
    private func ignoreUntil(_ targets: Set<Character>) -> Character? {
        while i < chars.count {
            if targets.contains(chars[i]) {
                return chars[i]
            }
            i += 1
        }
        return nil
    }

    // --- Mid level parses ---

    // Parses one "property: value" declaration. Returns (property, value).
    private func pair() throws -> (String, String) {
        skipWhitespace()
        let prop = try word()
        skipWhitespace()
        try literal(":")
        skipWhitespace()
        var val = try word()
        // Handle CSS function values like blur(5px), translate(10px, 20px)
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

    // MARK: - Shortand expansion

    // Dispatch - returns nil for regular (non-shorthand) properties.
    // To add new shorthand: one case line here.
    private static func expand(shorthand: String, tokens: [String]) -> [String: String]? {
        switch shorthand {
        case "font": return expandFont(tokens)
        case "border": return expandBorder(tokens, prefix: "border")
        case "outline": return expandBorder(tokens, prefix: "outline")
        case "margin": return expandBox(tokens, prefix: "margin")
        case "padding": return expandBox(tokens, prefix: "padding")
        default: return nil
        }
    }

    // font: [style] [weight] size family
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

    // border/outline: [width] [style] [color] - order-independent
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

    // margin/padding: 1-4 values -> top right bottom left
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
        ["font", "border", "outline", "margin", "padding"].contains(prop)
    }

    // Parse a rule body, separating normal from !important
    private func bodyParts() -> (normal: [String: String], important: [String: String]) {
        var normal: [String: String] = [:]
        var important: [String: String] = [:]

        while i < chars.count && chars[i] != "}" {
            if let (prop, val) = try? pair() {
                var tokens = [val]
                if CSSParser.isShortHand(prop) {
                    skipWhitespace()
                    while i < chars.count && chars[i] != ";" && chars[i] != "}" {
                        guard let t = try? word() else { break }
                        tokens.append(t)
                        skipWhitespace()
                    }
                }

                // Detect !important after the value(s).
                // "!" is not a word char so the shorthand loop already stopped here.
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
                    isImportant ? (important[prop] = val) : (normal[prop] = val)
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

    // Parses a CSS rule body: everything between { and }.
    // On a malformed declaration it skips to the next ";" and continues.
    func body() -> [String: String] {
        let parts = bodyParts()
        return parts.normal.merging(parts.important) { _, imp in imp }
    }

    // Converts one word token (e.g. "span.announce") into a simple or sequence selector.
    // Splits on "." to separate to optional tag from zero or more class names.
    private func parseSimpleSelector(_ token: String) -> any CSSSelector {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var selectors: [any CSSSelector] = []
        if let first = parts.first {
            let hashParts = first.split(separator: "#", omittingEmptySubsequences: false).map(
                String.init)
            if let tag = hashParts.first, !tag.isEmpty {
                selectors.append(TagSelector(tag: tag))
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

    // Reads one compound selector: optinal tag/class token, then zero or more :has(...) suffixes
    // Returns nil if nothing can be parsed (used as a break signal in selector()).
    private func parseCompoundSelector() -> (any CSSSelector)? {
        var parts: [any CSSSelector] = []

        if let w = try? word() {
            parts.append(parseSimpleSelector(w.lowercased()))
        }

        while i < chars.count && chars[i] == ":" {
            i += 1  // consume ":"
            guard let keyword = try? word() else { break }
            if keyword == "has" {
                guard (try? literal("(")) != nil else { break }
                skipWhitespace()
                let inner = selector()
                skipWhitespace()
                _ = try? literal(")")
                parts.append(HasSelector(inner: inner))
            } else {
                // treat as pseudo-class (e.g. :focus)
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

    // Parses a selector.
    // Collects all simple selectors into a flat array, then wraps in
    // DescendantSelector only when there are multiple parts.
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
        guard prop == "prefers-color-scheme" else { throw CSSParseError.parseError }
        return val  // "dark" or "light"
    }

    // Skips from current position to the end of a { ... } block.
    // Call this AFTER the opening "{" has been consumed.
    // Handles nested braces.
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

    // Parses a full stylesheet. Returns all valid (selector, body) rules.
    // Skips over malformed rules using error recovery.
    func parse() -> [(String?, any CSSSelector, [String: String])] {
        var rules: [(String?, any CSSSelector, [String: String])] = []
        var media: String? = nil
        while i < chars.count {
            skipWhitespace()
            do {
                if i < chars.count && chars[i] == "@" && media == nil {
                    media = try mediaQuery()
                    skipWhitespace()
                    try literal("{")
                    skipWhitespace()
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
                    _ = try? literal("{")  // consume the "{"
                    skipBlock()  // skip entire block, counting nested braces
                    skipWhitespace()
                } else if found == "}" {
                    _ = try? literal("}")
                    skipWhitespace()
                } else {
                    break
                }
            }
        }
        return rules
    }
}

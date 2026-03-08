import Foundation

// MARK: - CSSSelector Protocol
// Any selector can test whether it matches a DOM node and report it's priority.
// Higher priority wins when two rules set the same property.
protocol CSSSelector {
    var priority: Int { get }
    func matches(_ node: any DOMNode) -> Bool
}

// MARK: - TagSelector
// Matches Element nodes whose tag equals self.tag
// Example: TagSelector("p") matches every <p> element.
struct TagSelector: CSSSelector {
    let tag: String
    let priority: Int = 1

    func matches(_ node: any DOMNode) -> Bool {
        guard let element = node as? Element else {
            return false
        }
        return element.tag == tag
    }
}

// MARK: - DescendantSelector
// Matches a node when: the node matches `descendant` AND some ancestor
// of that node matches `ancestor`.
// Example: DescendantSelector(div, p) matches <p> elements inside a <div>.
struct DescendantSelector: CSSSelector {
    let ancestor: any CSSSelector
    let descendant: any CSSSelector
    var priority: Int { ancestor.priority + descendant.priority }

    func matches(_ node: any DOMNode) -> Bool {
        guard descendant.matches(node) else {
            return false
        }
        // Walk up the parent chain looking for a matching ancestor.
        var current = node.parent
        while let p = current {
            if ancestor.matches(p) { return true }
            current = p.parent
        }
        return false
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
        let prop = try word()
        skipWhitespace()
        try literal(":")
        skipWhitespace()
        let val = try word()
        return (prop.lowercased(), val)
    }

    // Parses a CSS rule body: everything between { and }.
    // On a malformed declaration it skips to the next ";" and continues.
    func body() -> [String: String] {
        var props: [String: String] = [:]
        while i < chars.count && chars[i] != "}" {
            if let (prop, val) = try? pair() {
                props[prop] = val
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
        return props
    }

    // Parses a selector.
    // A single word -> TagSelector. Multiple words separated by spaces ->
    // DescendantSelector chain, e.g. "div p span" builds nested selectors.
    func selector() -> any CSSSelector {
        var out: any CSSSelector = TagSelector(tag: (try? word())?.lowercased() ?? "")
        skipWhitespace()
        while i < chars.count && chars[i] != "{" {
            guard let tag = try? word() else { break }
            let inner = TagSelector(tag: tag.lowercased())
            out = DescendantSelector(ancestor: out, descendant: inner)
            skipWhitespace()
        }
        return out
    }

    // Parses a full stylesheet. Returns all valid (selector, body) rules.
    // Skips over malformed rules using error recovery.
    func parse() -> [(any CSSSelector, [String: String])] {
        var rules: [(any CSSSelector, [String: String])] = []
        while i < chars.count {
            skipWhitespace()
            let sel = selector()
            if (try? literal("{")) != nil {
                skipWhitespace()
                let props = body()
                if (try? literal("}")) != nil {
                    rules.append((sel, props))
                }
            } else {
                let found = ignoreUntil(["}"])
                if found == "}" {
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

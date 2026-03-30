import Foundation

// MARK: - HTMLParser
// Scans HTML one character at at time, building a DOM tree via a stack (unfinished).
// The stack holds the currently open (not-yet-closed) elements.
class HTMLParser {
    private let body: String
    private var unfinished: [Element] = []

    // Void elements that never have closing tags.
    static let selfClosingTags: Set<String> = [
        "area", "base", "br", "col", "embed",
        "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr",
    ]

    // Tags that belong inside <head>;
    // anything else triggers implicit <body>.
    static let headTags: Set<String> = [
        "base", "basefont", "bgsound",
        "noscript", "link", "meta",
        "title", "style", "script",
    ]

    // Formatting tags
    static let formattingTags: Set<String> = [
        "b", "i", "u", "em", "strong", "small",
        "s", "span", "code", "cite", "mark",
    ]

    init(body: String) {
        self.body = body
    }

    // Entry point: walks every character, dispatches to addText or addTag.
    // Returns the root DOM node (always an <html> Element after implicit_tags).
    func parse() -> any DOMNode {
        var text = ""
        var quoteChar: Character? = nil
        var inTag = false
        var inComment = false
        var inScript = false
        var i = body.startIndex

        while i < body.endIndex {
            let ch = body[i]

            if inScript {
                if isScriptClose(at: i) {
                    inScript = false
                    // don't advance i - let </script> fall through to normal tag processing
                } else {
                    // skip script content - don't parse it as HTML
                    i = body.index(i, offsetBy: 1)
                }
            } else if inComment {
                // Look for "--->" to end the comment
                if body[i...].hasPrefix("-->") {
                    inComment = false
                    i = body.index(i, offsetBy: 3)  // skip pas "-->"
                } else {
                    i = body.index(i, offsetBy: 1)  // skip comment content
                }
            } else if inTag {
                if let q = quoteChar {
                    // inside a quoted attribute value - only the matching quote exits
                    if ch == q { quoteChar = nil }
                    text.append(ch)
                    i = body.index(i, offsetBy: 1)
                } else if ch == "\"" || ch == "'" {
                    quoteChar = ch  // entering a quoted value
                    text.append(ch)
                    i = body.index(i, offsetBy: 1)
                } else if ch == ">" {
                    let tagText = text  // save before clearing
                    inTag = false
                    addTag(text)
                    text = ""
                    i = body.index(i, offsetBy: 1)
                    let firstWord =
                        tagText.split(separator: " ", maxSplits: 1)
                        .first.map { String($0).lowercased() } ?? ""
                    if firstWord == "script" {
                        inScript = true
                    }
                } else {
                    text.append(ch)
                    i = body.index(i, offsetBy: 1)
                }
            } else {
                // not in tag, not in comment
                if ch == "<" {
                    if body[i...].hasPrefix("<!--") {
                        inComment = true
                        if !text.isEmpty {
                            addText(text)
                            text = ""
                        }
                        i = body.index(i, offsetBy: 4)
                    } else {
                        inTag = true
                        if !text.isEmpty {
                            addText(text)
                            text = ""
                        }
                        text = ""
                        i = body.index(i, offsetBy: 1)
                    }
                } else if ch == ">" {
                    // bare ">" outside a tag - treat as text
                    text.append(ch)
                    i = body.index(i, offsetBy: 1)
                } else {
                    text.append(ch)
                    i = body.index(i, offsetBy: 1)
                }
            }
        }

        if !inTag && !text.isEmpty {
            addText(text)
        }
        return finish()
    }

    // Creates a TextNode and attaches it to innermost open element.
    // Whitespace-only strings are discarded - they carry no visual content.
    func addText(_ text: String) {
        if text.allSatisfy({ $0.isWhitespace }) {
            return
        }
        implicitTags(nil)
        let parent = unfinished.last!
        let processedText =
            text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&shy;", with: "\u{00AD}")
        let node = TextNode(text: processedText, parent: parent)
        parent.children.append(node)
    }

    func addTag(_ tag: String) {
        let (tagName, attributes) = getAttributes(tag)
        // Comments (<!--) and doctypes (<!DOCTYPE) start with "!" - skip them.
        if tagName.hasPrefix("!") {
            return
        }
        if tagName == "p" {
            closeIfOpen("p", stoppedBy: [])  // <p> can never contain another </p>
        }
        if tagName == "li" {
            closeIfOpen("li", stoppedBy: ["ul", "ol"])  // don't cross list boundaries
        }
        implicitTags(tagName)

        if tagName.hasPrefix("/") {
            let baseTag = String(tagName.dropFirst())

            // Mis-nested formatting tag: e.g. <b><i>text</b>
            if HTMLParser.formattingTags.contains(baseTag),
                let targetIdx = unfinished.lastIndex(where: { $0.tag == baseTag }),
                targetIdx < unfinished.count - 1
            {
                // Save formatting tags opened after (before) the target - they need reopening
                let toReopen = unfinished[(targetIdx + 1)...]
                    .filter({ HTMLParser.formattingTags.contains($0.tag) })
                    .map({ $0.tag })

                // Close everything above the target
                while unfinished.count > targetIdx + 1 {
                    let node = unfinished.removeLast()
                    unfinished.last!.children.append(node)
                }

                // Close the target itself
                if unfinished.count > 1 {
                    let node = unfinished.removeLast()
                    unfinished.last!.children.append(node)
                }

                // Reopen the formatting tags (same order they were originally opened)
                for tag in toReopen {
                    let parent: (any DOMNode)? = unfinished.last
                    let node = Element(tag: tag, attributes: [:], parent: parent)
                    unfinished.append(node)
                }
                return
            }

            // Normal close
            if unfinished.count == 1 { return }
            let node = unfinished.removeLast()
            unfinished.last!.children.append(node)
        } else if HTMLParser.selfClosingTags.contains(tagName) {
            // Self-closing: create and attach directly without pushing to stack.
            let parent = unfinished.last!
            let node = Element(tag: tagName, attributes: attributes, parent: parent)
            parent.children.append(node)
        } else {
            // Opening tag: push onto the stack; children follow until closing tag.
            let parent: (any DOMNode)? = unfinished.last
            let node = Element(tag: tagName, attributes: attributes, parent: parent)
            unfinished.append(node)
        }
    }

    // Parses a raw tag string like `a href="url" class="foo"` into (tag, attrs).
    // Tag name is lowercased; attribute keys are lowercased; quotes are stripped.
    private func getAttributes(_ raw: String) -> (String, [String: String]) {
        let raw = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        var parts: [String] = []
        var current = ""
        var inQuote: Character? = nil

        for ch in raw {
            if let q = inQuote {
                if ch == q { inQuote = nil }
                current.append(ch)
            } else if ch == "\"" || ch == "'" {
                inQuote = ch
                current.append(ch)
            } else if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" {
                if !current.isEmpty { parts.append(current) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { parts.append(current) }

        guard !parts.isEmpty else {
            return ("", [:])
        }
        let tagName = parts[0].lowercased()
        var attributes: [String: String] = [:]
        for pair in parts.dropFirst() {
            if let eqIdx = pair.firstIndex(of: "=") {
                let key = String(pair[pair.startIndex..<eqIdx]).lowercased()
                var value = String(pair[pair.index(after: eqIdx)...])
                // Strip surrounding single or double quotes from the value.
                if value.count > 1, value.first == "\"" || value.first == "'",
                    value.last == value.first
                {
                    value = String(value.dropFirst().dropLast())
                }
                attributes[key] = value
            } else {
                // Boolean attribute like `disabled` - store empty string.
                attributes[pair.lowercased()] = ""
            }
        }
        return (tagName, attributes)
    }

    // Closes all remaining open elements and returns the single root node.
    func finish() -> any DOMNode {
        if unfinished.isEmpty {
            implicitTags(nil)
        }
        while unfinished.count > 1 {
            let node = unfinished.removeLast()
            unfinished.last!.children.append(node)
        }
        return unfinished.removeLast()
    }

    // Inserts missing structural tags so the tree always html > head/body.
    // Called before adding any node; repeats until the stack is correct.
    private func implicitTags(_ tag: String?) {
        while true {
            let openTags = unfinished.map(\.tag)
            if openTags.isEmpty, tag != "html" {
                addTag("html")
            } else if openTags == ["html"], tag != "head", tag != "body", tag != "/html" {
                if let t = tag, HTMLParser.headTags.contains(t) {
                    addTag("head")
                } else {
                    addTag("body")
                }
            } else if openTags == ["html", "head"], tag != "/head",
                tag == nil || !HTMLParser.headTags.contains(tag!)
            {
                addTag("/head")
            } else {
                break
            }
        }
    }

    // Walks the stack from top; closes up to and including `target`.
    // Stops without closing if a tag in `stoppers` is encountered first.
    private func closeIfOpen(_ target: String, stoppedBy stoppers: Set<String>) {
        for idx in stride(from: unfinished.count - 1, through: 0, by: -1) {
            let t = unfinished[idx].tag
            if stoppers.contains(t) { return }  // hit a boundary - don't cross it
            if t == target {
                // pop everything from the top down to target (inclusive)
                while unfinished.count > idx {
                    let node = unfinished.removeLast()
                    if !unfinished.isEmpty {
                        unfinished.last!.children.append(node)
                    }
                }
                return
            }
        }
    }

    // Exit when you see the </script followed by one of: space, tab, `\v`, `\r`, or `>`.
    private func isScriptClose(at i: String.Index) -> Bool {
        let marker = "</script"
        guard body.distance(from: i, to: body.endIndex) >= marker.count else { return false }
        let end = body.index(i, offsetBy: marker.count)
        guard String(body[i..<end]).lowercased() == marker else { return false }
        if end >= body.endIndex { return true }
        return " \t\r\u{000B}/>".contains(body[end])
    }
}

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

    init(body: String) {
        self.body = body
    }

    // Entry point: walks every character, dispatches to addText or addTag.
    // Returns the root DOM node (always an <html> Element after implicit_tags).
    func parse() -> any DOMNode {
        var text = ""
        var inTag = false
        for ch in body {
            if ch == "<" {
                inTag = true
                if !text.isEmpty {
                    addText(text)
                }
                text = ""
            } else if ch == ">" {
                inTag = false
                addTag(text)
                text = ""
            } else {
                text.append(ch)
            }
        }
        if !inTag && !text.isEmpty {
            addText(text)
        }
        return finish()
    }

    // Creates a TextNode and attaches it to innermost open element.
    // Whitespace-only strings are discarded - they carry no visual content.
    private func addText(_ text: String) {
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

    private func addTag(_ tag: String) {
        let (tagName, attributes) = getAttributes(tag)
        // Comments (<!--) and doctypes (<!DOCTYPE) start with "!" - skip them.
        if tagName.hasPrefix("!") {
            return
        }
        implicitTags(tagName)

        if tagName.hasPrefix("/") {
            // Closing tag: pop the stack and attach the node to it's parent.
            // If only one element remains it's the root - don't pop it yet.
            if unfinished.count == 1 {
                return
            }
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
        let parts = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
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
    private func finish() -> any DOMNode {
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
}

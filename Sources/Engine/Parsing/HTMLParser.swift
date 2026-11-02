import Foundation

// MARK: - HTMLParser

@MainActor
class HTMLParser {
    private let body: String
    let dom: DOMTree = DOMTree()
    private var unfinished: [NodeID]
    private var sawTag: Bool

    static let selfClosingTags: Set<String> = [
        "area", "base", "br", "col", "embed",
        "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr",
    ]

    static let headTags: Set<String> = [
        "base", "basefont", "bgsound",
        "noscript", "link", "meta",
        "title", "style", "script",
    ]

    static let formattingTags: Set<String> = [
        "b", "i", "u", "em", "strong", "small",
        "s", "span", "code", "cite", "mark",
    ]

    init(body: String) {
        self.body = body
        self.unfinished = []
        self.sawTag = false
        self.unfinished = [dom.root]
    }

    func parse() -> DOMTree {
        var text: String = ""
        var quoteChar: Character? = nil
        var inTag: Bool = false
        var inComment: Bool = false
        var inScript: Bool = false
        var i: String.Index = body.startIndex

        while i < body.endIndex {
            let ch: Character = body[i]

            if inScript {
                if isScriptClose(at: i) {
                    inScript = false
                    if !text.isEmpty {
                        addText(text)
                        text = ""
                    }
                } else {
                    text.append(ch)
                    i = body.index(i, offsetBy: 1)
                }
            } else if inComment {
                if body[i...].hasPrefix("-->") {
                    inComment = false
                    i = body.index(i, offsetBy: 3)
                } else {
                    i = body.index(i, offsetBy: 1)
                }
            } else if inTag {
                if let q = quoteChar {
                    if ch == q { quoteChar = nil }
                    text.append(ch)
                    i = body.index(i, offsetBy: 1)
                } else if ch == "\"" || ch == "'" {
                    quoteChar = ch
                    text.append(ch)
                    i = body.index(i, offsetBy: 1)
                } else if ch == ">" {
                    let tagText: String = text
                    inTag = false
                    addTag(text)
                    text = ""
                    i = body.index(i, offsetBy: 1)
                    let firstWord: String =
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

    func addText(_ text: String) {
        let isWhiteSpace: Bool = text.allSatisfy({ $0.isWhitespace })
        if isWhiteSpace {
            guard let parent = unfinished.last else { return }
            if unfinished.count == 1, !sawTag { return }
            appendText(text, to: parent)
            return
        }
        implicitTags(nil)
        appendText(text, to: unfinished.last!)
    }

    private func appendText(_ text: String, to parent: NodeID) {
        let processedText: String =
            text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&shy;", with: "\u{00AD}")
        let node: NodeID = dom.createText(processedText)
        dom.append(node, to: parent)
    }

    func addTag(_ tag: String) {
        let (tagName, attributes) = getAttributes(tag)
        if tagName.hasPrefix("!") {
            return
        }
        sawTag = true
        if tagName == "html" {
            // The arena root is the document element.
            dom.setAttributes(attributes, of: dom.root)
            return
        }
        if tagName == "p" {
            closeIfOpen("p", stoppedBy: [])
        }
        if tagName == "li" {
            closeIfOpen("li", stoppedBy: ["ul", "ol"])
        }
        implicitTags(tagName)

        if tagName.hasPrefix("/") {
            let baseTag: String = String(tagName.dropFirst())

            if HTMLParser.formattingTags.contains(baseTag),
                let targetIdx = unfinished.lastIndex(where: { dom.tag(of: $0) == baseTag }),
                targetIdx < unfinished.count - 1
            {
                let toReopen: [String] = unfinished[(targetIdx + 1)...]
                    .filter({ HTMLParser.formattingTags.contains(dom.tag(of: $0) ?? "") })
                    .compactMap({ dom.tag(of: $0) })

                while unfinished.count > targetIdx + 1 {
                    let node: NodeID = unfinished.removeLast()
                    dom.append(node, to: unfinished.last!)
                }

                if unfinished.count > 1 {
                    let node: NodeID = unfinished.removeLast()
                    dom.append(node, to: unfinished.last!)
                }

                for tag in toReopen {
                    let node: NodeID = dom.createElement(tag: tag, attributes: [:])
                    unfinished.append(node)
                }
                return
            }

            if unfinished.count == 1 { return }
            let node: NodeID = unfinished.removeLast()
            dom.append(node, to: unfinished.last!)
        } else if HTMLParser.selfClosingTags.contains(tagName) {
            let parent: NodeID = unfinished.last!
            let node: NodeID = dom.createElement(tag: tagName, attributes: attributes)
            dom.append(node, to: parent)
        } else {
            let node: NodeID = dom.createElement(tag: tagName, attributes: attributes)
            unfinished.append(node)
        }
    }

    private func getAttributes(_ raw: String) -> (String, [String: String]) {
        let raw: String = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        var parts: [String] = []
        var current: String = ""
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
        let tagName: String = parts[0].lowercased()
        var attributes: [String: String] = [:]
        for pair in parts.dropFirst() {
            if let eqIdx = pair.firstIndex(of: "=") {
                let key: String = String(pair[pair.startIndex..<eqIdx]).lowercased()
                var value: String = String(pair[pair.index(after: eqIdx)...])
                if value.count > 1, value.first == "\"" || value.first == "'",
                    value.last == value.first
                {
                    value = String(value.dropFirst().dropLast())
                }
                attributes[key] = value
            } else {
                attributes[pair.lowercased()] = ""
            }
        }
        return (tagName, attributes)
    }

    func finish() -> DOMTree {
        if unfinished.count == 1, !sawTag {
            implicitTags(nil)
        }
        while unfinished.count > 1 {
            let node: NodeID = unfinished.removeLast()
            dom.append(node, to: unfinished.last!)
        }
        return dom
    }

    private func implicitTags(_ tag: String?) {
        while true {
            let openTags: [String] = unfinished.compactMap({ dom.tag(of: $0) })
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

    private func closeIfOpen(_ target: String, stoppedBy stoppers: Set<String>) {
        for idx in stride(from: unfinished.count - 1, through: 0, by: -1) {
            let t: String = dom.tag(of: unfinished[idx]) ?? ""
            if stoppers.contains(t) { return }
            if t == target {
                while unfinished.count > idx {
                    let node: NodeID = unfinished.removeLast()
                    if !unfinished.isEmpty {
                        dom.append(node, to: unfinished.last!)
                    }
                }
                return
            }
        }
    }

    private func isScriptClose(at i: String.Index) -> Bool {
        let marker: String = "</script"
        guard body[i] == "<" else { return false }
        guard let end: String.Index = body.index(i, offsetBy: marker.count, limitedBy: body.endIndex)
            else { return false }
        guard String(body[i..<end]).lowercased() == marker else { return false }
        if end >= body.endIndex { return true }
        return " \t\r\u{000B}/>".contains(body[end])
    }
}

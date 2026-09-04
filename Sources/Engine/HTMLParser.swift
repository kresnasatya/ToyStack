import Foundation

// MARK: - HTMLParser
class HTMLParser {
    private let body: String
    private var unfinished: [Element] = []

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
    }

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
                    let tagText = text
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
        if tagName.hasPrefix("!") {
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
            let baseTag = String(tagName.dropFirst())

            if HTMLParser.formattingTags.contains(baseTag),
                let targetIdx = unfinished.lastIndex(where: { $0.tag == baseTag }),
                targetIdx < unfinished.count - 1
            {
                let toReopen = unfinished[(targetIdx + 1)...]
                    .filter({ HTMLParser.formattingTags.contains($0.tag) })
                    .map({ $0.tag })

                while unfinished.count > targetIdx + 1 {
                    let node = unfinished.removeLast()
                    unfinished.last!.children.append(node)
                }

                if unfinished.count > 1 {
                    let node = unfinished.removeLast()
                    unfinished.last!.children.append(node)
                }

                for tag in toReopen {
                    let parent: (any DOMNode)? = unfinished.last
                    let node = Element(tag: tag, attributes: [:], parent: parent)
                    unfinished.append(node)
                }
                return
            }

            if unfinished.count == 1 { return }
            let node = unfinished.removeLast()
            unfinished.last!.children.append(node)
        } else if HTMLParser.selfClosingTags.contains(tagName) {
            let parent = unfinished.last!
            let node = Element(tag: tagName, attributes: attributes, parent: parent)
            parent.children.append(node)
        } else {
            let parent: (any DOMNode)? = unfinished.last
            let node = Element(tag: tagName, attributes: attributes, parent: parent)
            unfinished.append(node)
        }
    }

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

    private func closeIfOpen(_ target: String, stoppedBy stoppers: Set<String>) {
        for idx in stride(from: unfinished.count - 1, through: 0, by: -1) {
            let t = unfinished[idx].tag
            if stoppers.contains(t) { return }
            if t == target {
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

    private func isScriptClose(at i: String.Index) -> Bool {
        let marker = "</script"
        guard body.distance(from: i, to: body.endIndex) >= marker.count else { return false }
        let end = body.index(i, offsetBy: marker.count)
        guard String(body[i..<end]).lowercased() == marker else { return false }
        if end >= body.endIndex { return true }
        return " \t\r\u{000B}/>".contains(body[end])
    }
}

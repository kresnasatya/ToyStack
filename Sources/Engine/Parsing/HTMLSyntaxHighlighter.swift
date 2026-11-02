@MainActor
class HTMLSyntaxHighlighter: HTMLParser {
    private(set) var result = ""

    override func addText(_ text: String) {
        let escaped: String =
            text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        result += "<b>\(escaped)</b>"
    }

    override func addTag(_ tag: String) {
        let escaped: String =
            tag
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        result += "&lt;\(escaped)&gt;"
    }

    func highlight() -> String {
        _ = parse()
        return "<pre>\(result)</pre>"
    }

    override func finish() -> DOMTree {
        // The highlighter only reads tokens; it never builds implicit tags.
        return dom
    }
}

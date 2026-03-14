class HTMLSyntaxHighlighter: HTMLParser {
    private(set) var result = ""

    override func addText(_ text: String) {
        // Text content -> bold
        let escaped =
            text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        result += "<b>\(escaped)</b>"
    }

    override func addTag(_ tag: String) {
        // Tags -> escaped plain text (shows the raw tag markup)
        let escaped =
            tag
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        result += "&lt;\(escaped)&gt;"
    }

    func highlight() -> String {
        _ = parse()  // run the lexer - but we intercept addText/addTag
        return "<pre>\(result)</pre>"
    }

    override func finish() -> any DOMNode {
        return Element(tag: "html", attributes: [:], parent: nil)
    }
}

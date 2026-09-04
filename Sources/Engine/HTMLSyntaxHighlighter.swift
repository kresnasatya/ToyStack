class HTMLSyntaxHighlighter: HTMLParser {
    private(set) var result = ""

    override func addText(_ text: String) {
        let escaped =
            text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        result += "<b>\(escaped)</b>"
    }

    override func addTag(_ tag: String) {
        let escaped =
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

    override func finish() -> any DOMNode {
        return Element(tag: "html", attributes: [:], parent: nil)
    }
}

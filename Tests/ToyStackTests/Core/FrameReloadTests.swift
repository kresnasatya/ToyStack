import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct FrameReloadTests {
    private let rules: String = """
        html { width: 600px; }
        body { display: block; }
        p { display: block; }
        """

    @Test func replacingTheDocumentRebuildsInsteadOfReusingTheOldTree() {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="p">one</p>"#,
            rules: rules
        )
        #expect(page.frame.document != nil)

        page.frame.replaceDOM(HTMLParser(body: #"<p id="p">two</p>"#).parse())
        page.frame.setNeedsLayout()
        page.frame.render()

        let document: LayoutTree = page.frame.document!
        let words: [String] = treeToList(document, document.rootID)
            .filter({ document.isText($0) })
            .map({ document.textString($0) })
        #expect(words.contains("two"))
        #expect(!words.contains("one"))
    }
}

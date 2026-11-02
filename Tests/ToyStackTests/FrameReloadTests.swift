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

        page.frame.nodes = HTMLParser(body: #"<p id="p">two</p>"#).parse()
        page.frame.setNeedsLayout()
        page.frame.render()

        let words: [String] = treeToList(page.frame.document!)
            .compactMap({ $0 as? TextLayout })
            .map(\.word)
        #expect(words.contains("two"))
        #expect(!words.contains("one"))
    }
}

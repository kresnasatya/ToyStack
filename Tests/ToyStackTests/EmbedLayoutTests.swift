import CoreGraphics
import Testing

@testable import Engine

private let embedPageRules: String = """
    html { width: 400px; }
    body { display: block; }
    p { display: block; }
    """

@Suite(.serialized)
@MainActor
struct EmbedLayoutTests {

    @Test func imageWidthAttributeChangesLayoutWidth() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><img width="40"></p>"#,
            rules: embedPageRules
        )
        let image: ElementRef = try #require(page.firstElement(tag: "img"))
        let before: LayoutID = try #require(page.firstEmbedID(in: image))
        #expect(page.tree.width(before) == 40)
        let beforeWidth: CGFloat = page.tree.width(before)

        image.attributes["width"] = "80"
        LayoutInvalidation.attributesChanged(page.ref(of: image))
        page.frame.setNeedsRender()
        page.frame.render()

        let after: LayoutID = try #require(page.firstEmbedID(in: image))
        #expect(page.tree.width(after) == 80)
        #expect(page.tree.width(after) - beforeWidth == 40)
    }

    @Test func iframeHeightAttributeChangesLayoutHeight() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><iframe height="80"></iframe></p>"#,
            rules: embedPageRules
        )
        let iframe: ElementRef = try #require(page.firstElement(tag: "iframe"))
        let before: LayoutID = try #require(page.firstEmbedID(in: iframe))
        #expect(page.tree.height(before) == 82)
        let beforeHeight: CGFloat = page.tree.height(before)

        iframe.attributes["height"] = "120"
        LayoutInvalidation.attributesChanged(page.ref(of: iframe))
        page.frame.setNeedsRender()
        page.frame.render()

        let after: LayoutID = try #require(page.firstEmbedID(in: iframe))
        #expect(page.tree.height(after) == 122)
        #expect(page.tree.height(after) - beforeHeight == 40)
    }

    @Test func inputFontSizeChangesHeightAndAscent() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><input></p>"#,
            rules: embedPageRules
        )
        let input: ElementRef = try #require(page.firstElement(tag: "input"))
        let before: LayoutID = try #require(page.firstEmbedID(in: input))
        #expect(page.tree.height(before) == inlineDefaultFont.linespace)
        let beforeHeight: CGFloat = page.tree.height(before)

        input.attributes["style"] = "font-size: 32px"
        page.frame.setNeedsRender()
        page.frame.render()

        let after: LayoutID = try #require(page.firstEmbedID(in: input))
        let expected: BrowserFont = getFont(size: 32, weight: "normal", style: "roman")
        #expect(page.tree.height(after) == expected.linespace)
        #expect(page.tree.ascent(after) == expected.linespace)
        #expect(page.tree.height(after) > beforeHeight)
    }

    @Test func checkboxWidthMatchesFontLineSpace() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><input type="checkbox" style="font-size: 32px"></p>"#,
            rules: embedPageRules
        )
        let checkbox: ElementRef = try #require(page.firstElement(tag: "input"))
        let layout: LayoutID = try #require(page.firstEmbedID(in: checkbox))
        let expected: BrowserFont = getFont(size: 32, weight: "normal", style: "roman")
        #expect(page.tree.width(layout) == expected.linespace)
        #expect(page.tree.height(layout) == expected.linespace)
    }
}

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
        let before: LayoutRef = try #require(page.firstEmbed(in: image))
        #expect(before.width == 40)
        let beforeWidth: CGFloat = before.width

        image.attributes["width"] = "80"
        LayoutInvalidation.attributesChanged(page.ref(of: image))
        page.frame.setNeedsRender()
        page.frame.render()

        let after: LayoutRef = try #require(page.firstEmbed(in: image))
        #expect(after.width == 80)
        #expect(after.width - beforeWidth == 40)
    }

    @Test func iframeHeightAttributeChangesLayoutHeight() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><iframe height="80"></iframe></p>"#,
            rules: embedPageRules
        )
        let iframe: ElementRef = try #require(page.firstElement(tag: "iframe"))
        let before: LayoutRef = try #require(page.firstEmbed(in: iframe))
        #expect(before.height == 82)
        let beforeHeight: CGFloat = before.height

        iframe.attributes["height"] = "120"
        LayoutInvalidation.attributesChanged(page.ref(of: iframe))
        page.frame.setNeedsRender()
        page.frame.render()

        let after: LayoutRef = try #require(page.firstEmbed(in: iframe))
        #expect(after.height == 122)
        #expect(after.height - beforeHeight == 40)
    }

    @Test func inputFontSizeChangesHeightAndAscent() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><input></p>"#,
            rules: embedPageRules
        )
        let input: ElementRef = try #require(page.firstElement(tag: "input"))
        let before: LayoutRef = try #require(page.firstEmbed(in: input))
        #expect(before.height == inlineDefaultFont.linespace)
        let beforeHeight: CGFloat = before.height

        input.attributes["style"] = "font-size: 32px"
        page.frame.setNeedsRender()
        page.frame.render()

        let after: LayoutRef = try #require(page.firstEmbed(in: input))
        let expected: BrowserFont = getFont(size: 32, weight: "normal", style: "roman")
        #expect(after.height == expected.linespace)
        #expect(after.ascent == expected.linespace)
        #expect(after.height > beforeHeight)
    }

    @Test func checkboxWidthMatchesFontLineSpace() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><input type="checkbox" style="font-size: 32px"></p>"#,
            rules: embedPageRules
        )
        let checkbox: ElementRef = try #require(page.firstElement(tag: "input"))
        let layout: LayoutRef = try #require(page.firstEmbed(in: checkbox))
        let expected: BrowserFont = getFont(size: 32, weight: "normal", style: "roman")
        #expect(layout.width == expected.linespace)
        #expect(layout.height == expected.linespace)
    }
}

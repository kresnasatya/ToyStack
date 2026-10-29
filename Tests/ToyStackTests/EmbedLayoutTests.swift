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
        let image: Element = try #require(page.firstElement(tag: "img"))
        let before: ImageLayout = try #require(page.firstLayout(ImageLayout.self, in: image))
        #expect(before.width == 40)

        image.attributes["width"] = "80"
        LayoutInvalidation.attributesChanged(image)
        page.frame.setNeedsRender()
        page.frame.render()

        let after: ImageLayout = try #require(page.firstLayout(ImageLayout.self, in: image))
        #expect(after.width == 80)
        #expect(after.width - before.width == 40)
    }

    @Test func iframeHeightAttributeChangesLayoutHeight() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><iframe height="80"></iframe></p>"#,
            rules: embedPageRules
        )
        let iframe: Element = try #require(page.firstElement(tag: "iframe"))
        let before: IframeLayout = try #require(page.firstLayout(IframeLayout.self, in: iframe))
        #expect(before.height == 82)

        iframe.attributes["height"] = "120"
        LayoutInvalidation.attributesChanged(iframe)
        page.frame.setNeedsRender()
        page.frame.render()

        let after: IframeLayout = try #require(page.firstLayout(IframeLayout.self, in: iframe))
        #expect(after.height == 122)
        #expect(after.height - before.height == 40)
    }

    @Test func inputFontSizeChangesHeightAndAscent() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><input></p>"#,
            rules: embedPageRules
        )
        let input: Element = try #require(page.firstElement(tag: "input"))
        let before: InputLayout = try #require(page.firstLayout(InputLayout.self, in: input))
        #expect(before.height == inlineDefaultFont.linespace)

        input.attributes["style"] = "font-size: 32px"
        page.frame.setNeedsRender()
        page.frame.render()

        let after: InputLayout = try #require(page.firstLayout(InputLayout.self, in: input))
        let expected: BrowserFont = getFont(size: 32, weight: "normal", style: "roman")
        #expect(after.height == expected.linespace)
        #expect(after.ascentField.get() == expected.linespace)
        #expect(after.height > before.height)
    }

    @Test func checkboxWidthMatchesFontLineSpace() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><input type="checkbox" style="font-size: 32px"></p>"#,
            rules: embedPageRules
        )
        let checkbox: Element = try #require(page.firstElement(tag: "input"))
        let layout: InputLayout = try #require(page.firstLayout(InputLayout.self, in: checkbox))
        let expected: BrowserFont = getFont(size: 32, weight: "normal", style: "roman")
        #expect(layout.width == expected.linespace)
        #expect(layout.height == expected.linespace)
    }
}

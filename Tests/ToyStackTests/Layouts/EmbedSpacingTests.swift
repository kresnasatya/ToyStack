import CoreGraphics
import Testing

@testable import Engine

/// The space between an embed and the words around it: one space on each
/// side, the same room line breaking keeps for it.
@Suite(.serialized)
@MainActor
struct EmbedSpacingTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        p { display: block; }
        """

    private func page(_ html: String, rules: String = "") -> LayoutTestPage {
        return LayoutTestPage(html: html, rules: Self.baseRules + rules)
    }

    private func word(_ page: LayoutTestPage, _ text: String) throws -> LayoutID {
        let paragraph: ElementRef = try #require(page.firstElement(tag: "p"))
        return try #require(page.firstLayoutID(in: paragraph, where: { id, tree in
            tree.isText(id) && tree.textString(id) == text
        }))
    }

    private func image(_ page: LayoutTestPage) throws -> LayoutID {
        let element: ElementRef = try #require(page.firstElement(tag: "img"))
        return try #require(page.firstEmbedID(in: element))
    }

    @Test func wordAfterAnImageStartsOneSpaceAfterIt() throws {
        let page: LayoutTestPage = page(#"<p>before <img width="50" height="20"> after</p>"#)
        let image: LayoutID = try image(page)
        let after: LayoutID = try word(page, "after")

        #expect(page.tree.x(after) == page.tree.selfRect(image).right + page.tree.font(image).spaceWidth)
    }

    @Test func imageAfterAWordStartsOneSpaceAfterIt() throws {
        let page: LayoutTestPage = page(#"<p>before <img width="50" height="20"> after</p>"#)
        let image: LayoutID = try image(page)
        let before: LayoutID = try word(page, "before")
        let font: BrowserFont = page.tree.font(before)

        #expect(page.tree.selfRect(image).left == page.tree.x(before) + font.measure("before") + font.spaceWidth)
    }

    @Test func borderedSpanEndsAtTheImageInsideIt() throws {
        let page: LayoutTestPage = page(
            #"<p><span id="s">x <img width="50" height="20"></span> after</p>"#,
            rules: "#s { border: 2px solid red; }"
        )
        let image: LayoutID = try image(page)
        let line: LayoutID = try #require(page.tree.parentID(of: image))
        let fragment: InlineBoxFragment = try #require(page.tree[line: line].inlineBoxes.fragments.first)

        #expect(fragment.rect.right + page.tree.x(line) == page.tree.selfRect(image).right + 2)
    }
}

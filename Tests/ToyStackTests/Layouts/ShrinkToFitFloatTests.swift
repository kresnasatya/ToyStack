import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ShrinkToFitFloatTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        div { display: block; }
        """

    private func page(_ html: String, _ rules: String) -> LayoutTestPage {
        return LayoutTestPage(html: html, rules: Self.baseRules + rules)
    }

    private func floatWidth(_ page: LayoutTestPage) throws -> CGFloat {
        return page.tree.width(try #require(page.firstElement(id: "f")?.ref.layoutID))
    }

    private var font: BrowserFont { getFont(size: 16, weight: "normal", style: "roman") }

    @Test func autoWidthFloatHugsShortText() throws {
        let page: LayoutTestPage = page(#"<div id="f">Hello there</div>"#, "#f { float: left; }")
        let expected: CGFloat = font.measure("Hello") + font.measure("there") + 2 * font.spaceWidth
        #expect(abs(try floatWidth(page) - expected) < 0.001)
    }

    @Test func longTextFillsTheAvailableWidth() throws {
        let words: String = Array(repeating: "word", count: 200).joined(separator: " ")
        let page: LayoutTestPage = page(#"<div id="f">\#(words)</div>"#, "#f { float: left; padding: 0 10px; }")
        #expect(try floatWidth(page) == 580)
    }

    @Test func longestWordWinsInANarrowParent() throws {
        let page: LayoutTestPage = page(
            #"<div id="box"><div id="f">a Supercalifragilistic b</div></div>"#,
            "#box { width: 50px; } #f { float: left; }"
        )
        let expected: CGFloat = font.measure("Supercalifragilistic") + font.spaceWidth
        #expect(abs(try floatWidth(page) - expected) < 0.001)
    }

    @Test func blockChildWithAFixedWidthSetsTheFloor() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"><div id="inner"></div>Hi</div>"#,
            "#f { float: right; } #inner { width: 150px; margin-left: 10px; border: 2px solid black; }"
        )
        #expect(try floatWidth(page) == 164)
    }

    @Test func lineBreakSplitsThePreferredWidth() throws {
        let page: LayoutTestPage = page(#"<div id="f">one two<br>three</div>"#, "#f { float: left; }")
        let expected: CGFloat = font.measure("one") + font.measure("two") + 2 * font.spaceWidth
        #expect(abs(try floatWidth(page) - expected) < 0.001)
    }

    @Test func biggerTextWidensTheFloat() throws {
        let page: LayoutTestPage = page(
            #"<div id="f">Hello there</div><div id="next">after</div>"#,
            "#f { float: left; }"
        )
        let before: CGFloat = try floatWidth(page)
        let f: ElementRef = try #require(page.firstElement(id: "f"))
        InlineStyle.set(f, property: "font-size", value: "32px")
        page.frame.setNeedsStyle(f.ref)
        page.frame.render()

        #expect(try floatWidth(page) > before * 1.5)
        expectIncrementalMatchesFull(page)
    }
}

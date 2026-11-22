import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ButtonLayoutTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        p { display: block; }
        button { font-size: 16px; padding: 2px 7px; border: 1px solid black; }
        """

    private func page(_ html: String, rules: String = "") -> LayoutTestPage {
        return LayoutTestPage(html: html, rules: Self.baseRules + rules)
    }

    private func button(_ page: LayoutTestPage) throws -> LayoutID {
        let element: ElementRef = try #require(page.firstElement(tag: "button"))
        return try #require(page.embedID(in: element, .button))
    }

    /// The words of each line inside the button, in order.
    private func labelLines(_ page: LayoutTestPage, _ button: LayoutID) -> [[LayoutID]] {
        return page.tree.childrenIDs(of: button).map({ line in
            page.tree.childrenIDs(of: line).filter({ page.tree.isText($0) })
        })
    }

    private func word(_ page: LayoutTestPage, _ text: String, in button: LayoutID) throws -> LayoutID {
        return try #require(labelLines(page, button).joined().first(where: { page.tree.textString($0) == text }))
    }

    private func boxWidth(_ page: LayoutTestPage, _ button: LayoutID) -> CGFloat {
        let box: Rect = page.tree.selfRect(button)
        return box.right - box.left
    }

    @Test func buttonShrinksToItsLabel() throws {
        let page: LayoutTestPage = page(#"<p><button>Go</button></p>"#)
        let button: LayoutID = try button(page)
        let font: BrowserFont = page.tree.font(button)

        #expect(page.tree.width(button) == font.measure("Go"))
        #expect(boxWidth(page, button) == font.measure("Go") + 16)
    }

    @Test func labelWithSeveralWordsStaysOnOneLine() throws {
        let page: LayoutTestPage = page(#"<p><button>Save all changes</button></p>"#)
        let button: LayoutID = try button(page)
        let font: BrowserFont = page.tree.font(button)
        let expected: CGFloat = font.measure("Save") + font.spaceWidth
            + font.measure("all") + font.spaceWidth
            + font.measure("changes")

        #expect(labelLines(page, button).count == 1)
        #expect(page.tree.width(button) == expected)
    }

    @Test func shorterLineIsCenteredInTheButton() throws {
        let page: LayoutTestPage = page(#"<p><button>Delete everything<br>OK</button></p>"#)
        let button: LayoutID = try button(page)
        let font: BrowserFont = page.tree.font(button)
        let ok: LayoutID = try word(page, "OK", in: button)
        let delete: LayoutID = try word(page, "Delete", in: button)

        #expect(labelLines(page, button).count == 2)
        #expect(page.tree.x(delete) == page.tree.x(button))
        #expect(page.tree.x(ok) - page.tree.x(button) == (page.tree.width(button) - font.measure("OK")) / 2)
    }

    @Test func narrowParagraphWrapsTheLabelInsideIt() throws {
        let page: LayoutTestPage = page(
            #"<p id="narrow"><button>alpha beta gamma delta</button></p>"#,
            rules: "#narrow { width: 120px; }"
        )
        let button: LayoutID = try button(page)
        let paragraph: ElementRef = try #require(page.firstElement(id: "narrow"))
        let block: LayoutID = try #require(page.layoutID(of: paragraph))

        #expect(labelLines(page, button).count > 1)
        #expect(boxWidth(page, button) == page.tree.width(block))
        for line in labelLines(page, button) {
            let last: LayoutID = try #require(line.last)
            let end: CGFloat = page.tree.x(last) + page.tree.font(last).measure(page.tree.textString(last))
            #expect(end <= page.tree.x(button) + page.tree.width(button))
        }
    }

    @Test func wordAfterTheButtonFollowsItsWidth() throws {
        let page: LayoutTestPage = page(#"<p><button>Go</button> after</p>"#)
        let button: LayoutID = try button(page)
        let paragraph: ElementRef = try #require(page.firstElement(tag: "p"))
        let after: LayoutID = try #require(page.firstLayoutID(in: paragraph, where: { id, tree in
            tree.isText(id) && tree.textString(id) == "after"
        }))

        #expect(page.tree.x(after) == page.tree.selfRect(button).right + page.tree.font(button).spaceWidth)
    }

    @Test func inputInsideTheLabelKeepsTheLabelOnOneLine() throws {
        let page: LayoutTestPage = page(#"<p><button>Pick <input type="checkbox"> this</button></p>"#)
        let button: LayoutID = try button(page)
        let this: LayoutID = try word(page, "this", in: button)

        #expect(page.tree.childrenIDs(of: button).count == 1)
        #expect(page.tree.x(this) + page.tree.font(this).measure("this") == page.tree.x(button) + page.tree.width(button))
    }

    @Test func fontChangeInsideTheLabelResizesTheButton() throws {
        let page: LayoutTestPage = page(#"<p><button>Go <b id="inner">on</b></button> after</p>"#)
        let inner: ElementRef = try #require(page.firstElement(id: "inner"))
        let before: CGFloat = page.tree.width(try button(page))

        InlineStyle.set(inner, property: "font-size", value: "32px")
        page.frame.setNeedsStyle(inner.ref)
        page.frame.render()

        #expect(page.tree.width(try button(page)) > before)
        expectIncrementalMatchesFull(page)
    }

    @Test func editingTheLabelResizesTheButton() throws {
        let page: LayoutTestPage = page(#"<p><button>Go</button> after</p>"#)
        let element: ElementRef = try #require(page.firstElement(tag: "button"))
        let text: TextRef = try #require(element.children.first?.text)
        let before: CGFloat = page.tree.width(try button(page))

        text.append(" further")
        page.frame.setNeedsRender()
        page.frame.render()

        let button: LayoutID = try button(page)
        let font: BrowserFont = page.tree.font(button)
        #expect(page.tree.width(button) > before)
        #expect(page.tree.width(button) == font.measure("Go") + font.spaceWidth + font.measure("further"))
        expectIncrementalMatchesFull(page)
    }

    @Test func fontSizeChangeResizesTheButton() throws {
        let page: LayoutTestPage = page(#"<p><button>Go</button> after</p>"#)
        let element: ElementRef = try #require(page.firstElement(tag: "button"))

        InlineStyle.set(element, property: "font-size", value: "24px")
        page.frame.setNeedsStyle(element.ref)
        page.frame.render()

        let button: LayoutID = try button(page)
        #expect(page.tree.width(button) == page.tree.font(button).measure("Go"))
        expectIncrementalMatchesFull(page)
    }

    @Test func narrowingTheParagraphWrapsTheLabel() throws {
        let page: LayoutTestPage = page(#"<p id="box"><button>alpha beta gamma delta</button></p>"#)
        let paragraph: ElementRef = try #require(page.firstElement(id: "box"))
        #expect(labelLines(page, try button(page)).count == 1)

        InlineStyle.set(paragraph, property: "width", value: "120px")
        page.frame.setNeedsStyle(paragraph.ref)
        page.frame.render()

        #expect(labelLines(page, try button(page)).count > 1)
        expectIncrementalMatchesFull(page)
    }
}

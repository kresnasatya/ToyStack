import CoreGraphics
import Testing

@testable import Engine

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

    private func buttons(_ page: LayoutTestPage) throws -> [LayoutID] {
        let elements: [ElementRef] = treeToList(page.frame.nodes)
            .compactMap({ $0.element })
            .filter({ $0.tag == "button" })
        return try elements.map({ try #require(page.embedID(in: $0, .button)) })
    }

    private static let smallButtons: String = """
        button { font-size: 10px; padding: 2px 7px; border: 1px solid black; }
        """

    private static let largeButtons: String = """
        button { font-size: 30px; padding: 2px 7px; border: 1px solid black; }
        """

    @Test func wordAfterAnImageStartsOneSpaceAfterIt() throws {
        let page: LayoutTestPage = page(#"<p>before <img width="50" height="20"> after</p>"#)
        let image: LayoutID = try image(page)
        let after: LayoutID = try word(page, "after")

        #expect(page.tree.x(after) == page.tree.selfRect(image).right + page.tree.font(image).spaceWidth)
    }

    @Test func spaceAfterAButtonTakesTheFontOfTheWordAfterIt() throws {
        let page: LayoutTestPage = page(#"<p><button>Go</button> after</p>"#, rules: Self.smallButtons)
        let button: LayoutID = try #require(try buttons(page).first)
        let after: LayoutID = try word(page, "after")

        #expect(page.tree.x(after) == page.tree.selfRect(button).right + page.tree.font(after).spaceWidth)
    }

    @Test func spaceBetweenTwoButtonsTakesTheParagraphFont() throws {
        let page: LayoutTestPage = page(#"<p><button>A</button> <button>B</button></p>"#, rules: Self.smallButtons)
        let pair: [LayoutID] = try buttons(page)
        let paragraph: ElementRef = try #require(page.firstElement(tag: "p"))
        let block: LayoutID = try #require(page.layoutID(of: paragraph))
        let space: CGFloat = page.tree.fontFor(paragraph.id, zoom: page.tree.zoom(block)).spaceWidth

        #expect(pair.count == 2)
        #expect(page.tree.selfRect(pair[1]).left == page.tree.selfRect(pair[0]).right + space)
    }

    @Test func spanFontChangeMovesTheSecondButton() throws {
        let page: LayoutTestPage = page(
            #"<p><span id="s"><button>A</button> <button>B</button></span></p>"#,
            rules: Self.smallButtons
        )
        let span: ElementRef = try #require(page.firstElement(id: "s"))

        InlineStyle.set(span, property: "font-size", value: "40px")
        page.frame.setNeedsStyle(span.ref)
        page.frame.render()

        let pair: [LayoutID] = try buttons(page)
        let line: LayoutID = try #require(page.tree.parentID(of: pair[0]))
        let block: LayoutID = try #require(page.tree.parentID(of: line))
        let space: CGFloat = page.tree.fontFor(span.id, zoom: page.tree.zoom(block)).spaceWidth
        #expect(page.tree.selfRect(pair[1]).left == page.tree.selfRect(pair[0]).right + space)
        expectIncrementalMatchesFull(page)
    }

    @Test func wordThatFitsAfterALargeButtonStaysOnItsLine() throws {
        let page: LayoutTestPage = page(#"<p id="p"><button>Go</button> after</p>"#, rules: Self.largeButtons)
        let after: LayoutID = try word(page, "after")
        let font: BrowserFont = page.tree.font(after)
        let button: LayoutID = try #require(try buttons(page).first)
        let box: Rect = page.tree.selfRect(button)
        let fit: CGFloat = (box.right - box.left) + font.spaceWidth + font.measure("after") + font.spaceWidth + 0.5
        let paragraph: ElementRef = try #require(page.firstElement(id: "p"))

        InlineStyle.set(paragraph, property: "width", value: "\(fit)px")
        page.frame.setNeedsStyle(paragraph.ref)
        page.frame.render()

        let placed: LayoutID = try word(page, "after")
        let line: LayoutID? = page.tree.parentID(of: try #require(try buttons(page).first))
        #expect(page.tree.parentID(of: placed) == line)
        expectIncrementalMatchesFull(page)
    }

    @Test func floatAroundASmallButtonKeepsTheWordAfterIt() throws {
        let page: LayoutTestPage = page(
            #"<p><span id="f"><button>Go</button> after</span></p>"#,
            rules: Self.smallButtons + "#f { float: left; }"
        )
        let after: LayoutID = try word(page, "after")
        let button: LayoutID = try #require(try buttons(page).first)

        #expect(page.tree.parentID(of: after) == page.tree.parentID(of: button))
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

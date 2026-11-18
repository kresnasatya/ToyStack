import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct PageTextTests {
    private static let rules: String = """
        html { width: 600px; }
        body { display: block; }
        p { display: block; }
        pre { display: block; white-space: pre; }
        """

    private func range(
        _ page: LayoutTestPage,
        _ unit: TextUnit,
        at point: CGPoint
    ) throws -> TextRange {
        return try #require(PageText(tree: page.tree).range(of: unit, atX: point.x, y: point.y))
    }

    private func string(_ page: LayoutTestPage, covering ranges: [TextRange]) throws -> String {
        let text: PageText = PageText(tree: page.tree)
        return text.string(in: try #require(text.span(covering: ranges)))
    }

    private func textNode(of element: ElementRef) throws -> NodeID {
        return try #require(element.ref.children.first(where: { $0.text != nil })).id
    }

    private func lastElement(_ page: LayoutTestPage, tag: String) throws -> ElementRef {
        return try #require(treeToList(page.frame.nodes).compactMap({ $0.element }).last(where: { $0.tag == tag }))
    }

    @Test func pointInsideAWordLandsOnTheNearestGap() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>hello world</p>", rules: Self.rules)
        let node: NodeID = try textNode(of: try #require(page.firstElement(tag: "p")))

        let gap: TextRange = try range(page, .character, at: page.textPoint("world", offset: 2))

        #expect(gap.start == TextPosition(node: node, offset: 8))
        #expect(gap.end == gap.start)
    }

    @Test func pointLeftOfALineLandsOnItsStart() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>hello world</p>", rules: Self.rules)
        let node: NodeID = try textNode(of: try #require(page.firstElement(tag: "p")))
        let inside: CGPoint = page.textPoint("hello", offset: 0)

        let gap: TextRange = try range(page, .character, at: CGPoint(x: inside.x - 50, y: inside.y))

        #expect(gap.start == TextPosition(node: node, offset: 0))
    }

    @Test func pointBelowAllTextLandsOnTheEndOfTheLastLine() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>one</p><p>two three</p>", rules: Self.rules)
        let node: NodeID = try textNode(of: try lastElement(page, tag: "p"))
        let inside: CGPoint = page.textPoint("two", offset: 0)

        let gap: TextRange = try range(page, .character, at: CGPoint(x: inside.x + 500, y: inside.y + 400))

        #expect(gap.start == TextPosition(node: node, offset: 9))
    }

    @Test func wordUnitCoversTheWordUnderThePoint() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>hello wonderful world</p>", rules: Self.rules)

        let word: TextRange = try range(page, .word, at: page.textPoint("wonderful", offset: 4))

        #expect(try string(page, covering: [word]) == "wonderful")
    }

    @Test func wordUnitOnTheLastLetterStillCoversTheWord() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>hello world</p>", rules: Self.rules)
        let start: CGPoint = page.textPoint("hello", offset: 4)
        let end: CGPoint = page.textPoint("hello", offset: 5)

        let word: TextRange = try range(page, .word, at: CGPoint(x: (start.x + end.x) / 2 + 1, y: start.y))

        #expect(try string(page, covering: [word]) == "hello")
    }

    @Test func wordUnitStopsAtPunctuation() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>say hello, world</p>", rules: Self.rules)

        let word: TextRange = try range(page, .word, at: page.textPoint("hello", offset: 2))

        #expect(try string(page, covering: [word]) == "hello")
    }

    @Test func paragraphUnitCoversTheWholeBlock() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>one two</p><p>three four</p>", rules: Self.rules)

        let paragraph: TextRange = try range(page, .paragraph, at: page.textPoint("four", offset: 1))

        #expect(try string(page, covering: [paragraph]) == "three four")
    }

    @Test func textAcrossBlocksIsJoinedByANewline() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>one two</p><p>three four</p>", rules: Self.rules)
        let from: TextRange = try range(page, .character, at: page.textPoint("two", offset: 0))
        let to: TextRange = try range(page, .character, at: page.textPoint("three", offset: 5))

        #expect(try string(page, covering: [from, to]) == "two\nthree")
        #expect(try string(page, covering: [to, from]) == "two\nthree")
    }

    @Test func lineBreakElementBecomesANewline() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>one<br>two</p>", rules: Self.rules)

        let paragraph: TextRange = try range(page, .paragraph, at: page.textPoint("two", offset: 1))

        #expect(try string(page, covering: [paragraph]) == "one\ntwo")
    }

    @Test func softWrapBecomesASpace() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p>alpha beta gamma delta epsilon</p>",
            rules: Self.rules + "html { width: 90px; }"
        )
        let p: ElementRef = try #require(page.firstElement(tag: "p"))
        try #require(page.lineIDs(in: p).count > 1)

        let paragraph: TextRange = try range(page, .paragraph, at: page.textPoint("alpha", offset: 1))

        #expect(try string(page, covering: [paragraph]) == "alpha beta gamma delta epsilon")
    }

    @Test func preformattedLinesKeepTheirNewlines() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<pre>let a = 1\nlet b = 2</pre>",
            rules: Self.rules
        )

        let paragraph: TextRange = try range(page, .paragraph, at: page.textPoint("let b", offset: 1))

        #expect(try string(page, covering: [paragraph]) == "let a = 1\nlet b = 2")
    }

    @Test func selectionSurvivesTheTextWrappingDifferently() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p>alpha beta gamma delta epsilon</p>",
            rules: Self.rules
        )
        let from: TextRange = try range(page, .character, at: page.textPoint("beta", offset: 0))
        let to: TextRange = try range(page, .character, at: page.textPoint("delta", offset: 5))

        page.frame.setStyleRules(CSSParser(Self.rules + "html { width: 90px; }").parse().rules)
        page.frame.setNeedsRender()
        page.frame.render()
        try #require(page.lineIDs(in: try #require(page.firstElement(tag: "p"))).count > 1)

        #expect(try string(page, covering: [from, to]) == "beta gamma delta")
    }

    @Test func positionInTextThatIsNoLongerLaidOutResolvesToNothing() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>hello world</p>", rules: Self.rules)
        let gone: TextPosition = TextPosition(node: NodeID(raw: 999_999), offset: 0)

        #expect(PageText(tree: page.tree).span(covering: [TextRange(start: gone, end: gone)]) == nil)
    }

    @Test func pageWithoutTextHasNoPositions() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p></p>", rules: Self.rules)

        #expect(PageText(tree: page.tree).range(of: .character, atX: 10, y: 10) == nil)
    }
}

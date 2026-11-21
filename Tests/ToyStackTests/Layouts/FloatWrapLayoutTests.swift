import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct FloatWrapLayoutTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        div { display: block; }
        p { display: block; }
        """

    private static let words: String = Array(repeating: "word", count: 120).joined(separator: " ")

    private func page(_ html: String, _ rules: String) -> LayoutTestPage {
        return LayoutTestPage(html: html, rules: Self.baseRules + rules)
    }

    private func paragraph(_ page: LayoutTestPage) throws -> (block: LayoutID, lines: [LayoutID]) {
        let p: ElementRef = try #require(page.firstElement(id: "p"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))
        let lines: [LayoutID] = page.lineIDs(in: p)
        try #require(lines.count > 4)
        return (block, lines)
    }

    private func floatRect(_ page: LayoutTestPage) throws -> Rect {
        return page.tree.selfRect(try #require(page.firstElement(id: "f")?.ref.layoutID))
    }

    @Test func linesBesideALeftFloatStartAfterItsMarginBox() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><p id="p">\#(Self.words)</p>"#,
            "#f { float: left; width: 100px; height: 60px; margin-right: 10px; }"
        )
        let (block, lines) = try paragraph(page)
        let float: Rect = try floatRect(page)
        let first: LayoutID = lines[0]
        #expect(page.tree.x(first) == page.tree.x(block) + 110)
        #expect(page.tree.width(first) == page.tree.width(block) - 110)

        let below: LayoutID = try #require(lines.first(where: { page.tree.y($0) >= float.bottom }))
        #expect(page.tree.x(below) == page.tree.x(block))
        #expect(page.tree.width(below) == page.tree.width(block))
    }

    @Test func rightFloatShortensLinesFromTheRight() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><p id="p">\#(Self.words)</p>"#,
            "#f { float: right; width: 100px; height: 60px; }"
        )
        let (block, lines) = try paragraph(page)
        #expect(page.tree.x(lines[0]) == page.tree.x(block))
        #expect(page.tree.width(lines[0]) == page.tree.width(block) - 100)
    }

    @Test func wrappingBesideAFloatNeedsMoreLines() throws {
        let plain: LayoutTestPage = page(#"<p id="p">\#(Self.words)</p>"#, "")
        let wrapped: LayoutTestPage = page(
            #"<div id="f"></div><p id="p">\#(Self.words)</p>"#,
            "#f { float: left; width: 300px; height: 200px; }"
        )
        #expect(try paragraph(wrapped).lines.count > paragraph(plain).lines.count)
    }

    @Test func floatPushedIntoThePageMarginLeavesLinesAlone() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><p id="p">\#(Self.words)</p>"#,
            "#f { float: right; width: 100px; height: 60px; margin-right: -120px; }"
        )
        let (block, lines) = try paragraph(page)
        #expect(page.tree.x(lines[0]) == page.tree.x(block))
        #expect(page.tree.width(lines[0]) == page.tree.width(block))
    }

    @Test func lineTooNarrowBesideAFloatDropsBelowIt() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><p id="p">\#(Self.words)</p>"#,
            "#f { float: left; width: 590px; height: 50px; }"
        )
        let (block, lines) = try paragraph(page)
        let float: Rect = try floatRect(page)
        #expect(page.tree.y(lines[0]) == float.bottom)
        #expect(page.tree.x(lines[0]) == page.tree.x(block))
        let last: LayoutID = try #require(lines.last)
        #expect(page.tree.y(block) + page.tree.height(block) == page.tree.y(last) + page.tree.height(last))
    }

    @Test func growingAFloatUnderAnotherParentRewrapsTheParagraph() throws {
        let page: LayoutTestPage = page(
            #"<div id="ad"><div id="f"></div></div><p id="p">\#(Self.words)</p>"#,
            "#f { float: left; width: 100px; height: 20px; }"
        )
        let f: ElementRef = try #require(page.firstElement(id: "f"))
        InlineStyle.set(f, property: "height", value: "120px")
        page.frame.setNeedsStyle(f.ref)
        page.frame.render()

        let (block, lines) = try paragraph(page)
        let float: Rect = try floatRect(page)
        let beside: [LayoutID] = lines.filter({ page.tree.y($0) < float.bottom })
        #expect(beside.count > 2)
        #expect(beside.allSatisfy({ page.tree.x($0) == page.tree.x(block) + 100 }))
        expectIncrementalMatchesFull(page)
    }

    @Test func hidingTheFloatGivesLinesTheirFullWidthBack() throws {
        let page: LayoutTestPage = page(
            #"<div id="ad"><div id="f"></div></div><p id="p">\#(Self.words)</p>"#,
            "#f { float: left; width: 100px; height: 60px; }"
        )
        let f: ElementRef = try #require(page.firstElement(id: "f"))
        InlineStyle.set(f, property: "display", value: "none")
        page.frame.setNeedsStyle(f.ref)
        page.frame.render()

        let (block, lines) = try paragraph(page)
        #expect(lines.allSatisfy({ page.tree.x($0) == page.tree.x(block) }))
        #expect(lines.allSatisfy({ page.tree.width($0) == page.tree.width(block) }))
        expectIncrementalMatchesFull(page)
    }

    @Test func showingAFloatWrapsAParagraphThatWasFullWidth() throws {
        let page: LayoutTestPage = page(
            #"<div id="ad"><div id="f" style="display: none"></div></div><p id="p">\#(Self.words)</p>"#,
            "#f { float: right; width: 100px; height: 60px; }"
        )
        let f: ElementRef = try #require(page.firstElement(id: "f"))
        InlineStyle.set(f, property: "display", value: "block")
        page.frame.setNeedsStyle(f.ref)
        page.frame.render()

        let (block, lines) = try paragraph(page)
        #expect(page.tree.width(lines[0]) == page.tree.width(block) - 100)
        expectIncrementalMatchesFull(page)
    }

    @Test func paragraphBelowTheFloatsIsNotReplacedByAnUnrelatedChange() throws {
        let page: LayoutTestPage = page(
            """
            <div id="f"></div><p id="p">\(Self.words)</p>\
            <div id="spacer"></div><p id="far">\(Self.words)</p><div id="tail"></div>
            """,
            """
            #f { float: left; width: 100px; height: 60px; }
            #spacer { height: 400px; }
            #tail { height: 10px; }
            """
        )
        let tail: ElementRef = try #require(page.firstElement(id: "tail"))
        InlineStyle.set(tail, property: "height", value: "30px")
        page.frame.setNeedsStyle(tail.ref)
        profiler.reset()
        page.frame.render()

        // Only the paragraph beside the float re-checks; the one far below
        // keeps its lines.
        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect((metrics["layout.inline.place.setup"]?.count ?? 0) <= 1)
        expectIncrementalMatchesFull(page)
    }

    /// The paragraph starts 30px above the float, so only a line taller than
    /// the paragraph's own font reaches it.
    private static let lowFloatRules: String = """
        #f { float: left; width: 100px; height: 20px; }
        #p { margin-top: -30px; margin-bottom: 0; }
        """

    @Test func lineWithABigFontIsShortenedByAFloatBelowItsTop() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><p id="p"><span style="font-size: 48px">Big</span> \#(Self.words)</p>"#,
            Self.lowFloatRules
        )
        let (block, lines) = try paragraph(page)
        let float: Rect = try floatRect(page)
        #expect(page.tree.y(lines[0]) + page.tree.height(lines[0]) > float.top)
        #expect(page.tree.x(lines[0]) == page.tree.x(block) + 100)
    }

    @Test func lineWithATallImageUsesTheImageHeightForItsBand() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><p id="p"><img width="40" height="60"> \#(Self.words)</p>"#,
            Self.lowFloatRules
        )
        let (block, lines) = try paragraph(page)
        let float: Rect = try floatRect(page)
        #expect(page.tree.x(lines[0]) == page.tree.x(block) + 100)
        #expect(page.tree.y(lines[1]) >= float.bottom)
        #expect(page.tree.x(lines[1]) == page.tree.x(block))
        #expect(page.tree.width(lines[1]) == page.tree.width(block))
    }

    @Test func tallItemThatWouldHitTheFloatStartsTheNextLine() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><p id="p">\#(String(repeating: "word ", count: 10))<span style="font-size: 48px">Big</span> \#(Self.words)</p>"#,
            Self.lowFloatRules + "#f { width: 300px; }"
        )
        let (block, lines) = try paragraph(page)
        let float: Rect = try floatRect(page)
        let first: LayoutID = lines[0]
        #expect(page.tree.y(first) + page.tree.height(first) <= float.top)
        #expect(page.tree.x(first) == page.tree.x(block))
        let big: LayoutID = lines[1]
        #expect(page.tree.x(big) == page.tree.x(block) + 300)
    }
}

import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct InlineFloatLayoutTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        div { display: block; }
        p { display: block; margin-top: 0; margin-bottom: 0; }
        """

    private static let words: String = Array(repeating: "word", count: 120).joined(separator: " ")

    private func page(_ html: String, _ rules: String) -> LayoutTestPage {
        return LayoutTestPage(html: html, rules: Self.baseRules + rules)
    }

    private func block(_ page: LayoutTestPage, _ name: String) throws -> LayoutID {
        let element: ElementRef = try #require(page.firstElement(id: name))
        return try #require(page.firstBlockID(in: element))
    }

    private func rect(_ page: LayoutTestPage, _ name: String) throws -> Rect {
        return page.tree.selfRect(try #require(page.firstElement(id: name)?.ref.layoutID))
    }

    private func lines(_ page: LayoutTestPage, _ name: String) throws -> [LayoutID] {
        let found: [LayoutID] = page.lineIDs(in: try #require(page.firstElement(id: name)))
        try #require(found.count > 2)
        return found
    }

    @Test func floatedSpanKeepsTheParagraphInOnePiece() throws {
        let page: LayoutTestPage = page(
            #"<p id="p">before <span id="n">note</span> after \#(Self.words)</p>"#,
            "#n { float: right; width: 100px; }"
        )
        let p: LayoutID = try block(page, "p")
        let n: LayoutID = try #require(page.firstElement(id: "n")?.ref.layoutID)
        let blocks: [LayoutID] = page.tree.childrenIDs(of: p).filter({ page.tree.isBlock($0) })
        #expect(blocks == [n])
        #expect(page.tree.childrenIDs(of: try lines(page, "p")[0]).count >= 1)
    }

    @Test func floatSitsAtTheTopOfItsLineAndShortensTheLinesBesideIt() throws {
        let page: LayoutTestPage = page(
            #"<p id="p">before <span id="n">a note that is long enough to wrap</span> after \#(Self.words)</p>"#,
            "#n { float: right; width: 100px; }"
        )
        let p: LayoutID = try block(page, "p")
        let all: [LayoutID] = try lines(page, "p")
        let note: Rect = try rect(page, "n")
        #expect(note.top == page.tree.y(all[0]))
        #expect(note.right == page.tree.x(p) + page.tree.width(p))
        #expect(page.tree.width(all[1]) == page.tree.width(p) - 100)
        let below: LayoutID = try #require(all.first(where: { page.tree.y($0) >= note.bottom }))
        #expect(page.tree.width(below) == page.tree.width(p))
    }

    @Test func floatNestedInAnInlineElementIsFloatedToo() throws {
        let page: LayoutTestPage = page(
            #"<p id="p">before <span class="nc">x<span id="n">note</span></span> after \#(Self.words)</p>"#,
            "#n { float: left; width: 80px; }"
        )
        let p: LayoutID = try block(page, "p")
        let first: LayoutID = try lines(page, "p")[0]
        #expect(page.tree.x(first) == page.tree.x(p) + 80)
        #expect(page.tree.width(first) == page.tree.width(p) - 80)
        #expect(try rect(page, "n").left == page.tree.x(p))
    }

    @Test func noteInTheMarginLeavesTheLinesFullWidth() throws {
        let page: LayoutTestPage = page(
            #"<p id="p">before <span id="n">note</span> after \#(Self.words)</p>"#,
            "#n { float: right; width: 100px; margin-right: -120px; }"
        )
        let p: LayoutID = try block(page, "p")
        #expect(try lines(page, "p").allSatisfy({ page.tree.width($0) == page.tree.width(p) }))
        #expect(try rect(page, "n").left == page.tree.x(p) + page.tree.width(p) + 20)
    }

    @Test func notesInLaterParagraphsClearEarlierOnes() throws {
        let page: LayoutTestPage = page(
            """
            <p id="p1">one <span id="n1">\(Self.words)</span> two</p>\
            <p id="p2">three <span id="n2">note</span> four</p>
            """,
            ".note, #n1, #n2 { float: right; clear: right; width: 100px; margin-right: -120px; }"
        )
        let first: Rect = try rect(page, "n1")
        let second: Rect = try rect(page, "n2")
        #expect(second.top >= first.bottom)
        #expect(second.left == first.left)
    }

    @Test func floatedImageStartsTheLinesAfterIt() throws {
        let page: LayoutTestPage = page(
            #"<p id="p"><img id="i" width="50" height="40" style="float: left"> \#(Self.words)</p>"#,
            ""
        )
        let p: LayoutID = try block(page, "p")
        let image: Rect = try rect(page, "i")
        #expect(image.left == page.tree.x(p))
        #expect(image.right - image.left == 50)
        #expect(page.tree.x(try lines(page, "p")[0]) == page.tree.x(p) + 50)
    }

    @Test func growingANoteRewrapsTheNextParagraph() throws {
        let page: LayoutTestPage = page(
            """
            <p id="p1">one <span id="n">note</span> two</p>\
            <p id="p2">\(Self.words)</p>
            """,
            "#n { float: right; width: 100px; }"
        )
        let n: ElementRef = try #require(page.firstElement(id: "n"))
        InlineStyle.set(n, property: "height", value: "200px")
        page.frame.setNeedsStyle(n.ref)
        page.frame.render()

        let p2: LayoutID = try block(page, "p2")
        #expect(page.tree.width(try lines(page, "p2")[0]) == page.tree.width(p2) - 100)
        expectIncrementalMatchesFull(page)
    }

    @Test func hidingTheNoteGivesTheLinesTheirWidthBack() throws {
        let page: LayoutTestPage = page(
            #"<p id="p">before <span id="n">a note that is long enough to wrap</span> after \#(Self.words)</p>"#,
            "#n { float: right; width: 100px; }"
        )
        let n: ElementRef = try #require(page.firstElement(id: "n"))
        InlineStyle.set(n, property: "display", value: "none")
        page.frame.setNeedsStyle(n.ref)
        page.frame.render()

        let p: LayoutID = try block(page, "p")
        #expect(try lines(page, "p").allSatisfy({ page.tree.width($0) == page.tree.width(p) }))
        expectIncrementalMatchesFull(page)
    }

    @Test func footnotedParagraphKeepsItsLinesWhenNothingNearItChanges() throws {
        let page: LayoutTestPage = page(
            """
            <div id="column"></div>\
            <p id="p">before <span id="n">a note</span> after \(Self.words)</p>\
            <div id="tail"></div>
            """,
            """
            #column { float: right; width: 100px; height: 400px; margin-right: -120px; }
            #n { float: right; clear: right; width: 100px; margin-right: -120px; }
            #tail { height: 10px; }
            """
        )
        let tail: ElementRef = try #require(page.firstElement(id: "tail"))
        InlineStyle.set(tail, property: "height", value: "30px")
        page.frame.setNeedsStyle(tail.ref)
        profiler.reset()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(metrics["layout.inline.place.setup"] == nil)
        #expect(try rect(page, "n").top >= rect(page, "column").bottom)
        expectIncrementalMatchesFull(page)
    }

    @Test func editingTheNoteStillReplacesItsParagraph() throws {
        let page: LayoutTestPage = page(
            #"<p id="p">before <span id="n">note</span> after \#(Self.words)</p>"#,
            "#n { float: left; width: 100px; }"
        )
        let n: ElementRef = try #require(page.firstElement(id: "n"))
        let text: TextRef = try #require(n.children.first?.text)
        text.append(" that now runs on long enough to need several lines of its own")
        page.frame.setNeedsRender()
        page.frame.render()

        let p: LayoutID = try block(page, "p")
        let note: Rect = try rect(page, "n")
        let beside: [LayoutID] = try lines(page, "p").filter({ page.tree.y($0) < note.bottom })
        #expect(beside.count > 2)
        #expect(beside.allSatisfy({ page.tree.x($0) == page.tree.x(p) + 100 }))
        expectIncrementalMatchesFull(page)
    }
}

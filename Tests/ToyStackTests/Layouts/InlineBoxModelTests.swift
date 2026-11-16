import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct InlineBoxModelTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        p { display: block; }
        """

    private func lines(_ page: LayoutTestPage) throws -> [LayoutID] {
        let paragraph: ElementRef = try #require(page.firstElement(tag: "p"))
        return page.lineIDs(in: paragraph)
    }

    private func textChild(_ page: LayoutTestPage, on line: LayoutID, of node: NodeID) throws -> Int {
        let children: [LayoutID] = page.tree.childrenIDs(of: line)
        return try #require(children.firstIndex(where: { page.tree.domID(of: $0) == node }))
    }

    private func spanText(_ page: LayoutTestPage, _ id: String) throws -> NodeID {
        let span: ElementRef = try #require(page.firstElement(id: id))
        return try #require(span.children.first?.id)
    }

    @Test func spanPaddingAndBorderOpenGapsAroundItsText() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>a <span id="s">b</span> c</p>"#,
            rules: Self.baseRules + "#s { padding: 0 6px; border-left: 2px solid red; border-right: 1px solid red; }"
        )
        let line: LayoutID = try #require(try lines(page).first)
        let children: [LayoutID] = page.tree.childrenIDs(of: line)
        let widths: [CGFloat] = page.tree[line: line].content.inlineWidths
        let b: Int = try textChild(page, on: line, of: try spanText(page, "s"))

        #expect(page.tree.x(children[b]) == page.tree.x(children[b - 1]) + widths[b - 1] + 8)
        #expect(page.tree.x(children[b + 1]) == page.tree.x(children[b]) + widths[b] + 7)
    }

    /// A right-to-left element that starts and ends on one line still has
    /// its left edges on the left and its right edges on the right.
    @Test func rightToLeftSpanOnOneLineKeepsEachEdgeOnItsOwnSide() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>a <span id="s">b</span> c</p>"#,
            rules: Self.baseRules + """
                p { direction: rtl; }
                #s { padding: 0 6px; border-left: 2px solid red; border-right: 5px solid red; }
                """
        )
        let line: LayoutID = try #require(try lines(page).first)
        let children: [LayoutID] = page.tree.childrenIDs(of: line)
        let widths: [CGFloat] = page.tree[line: line].content.inlineWidths
        let b: Int = try textChild(page, on: line, of: try spanText(page, "s"))

        #expect(page.tree.x(children[b]) == page.tree.x(children[b - 1]) + widths[b - 1] + 8)
        #expect(page.tree.x(children[b + 1]) == page.tree.x(children[b]) + widths[b] + 11)
    }

    @Test func spanFragmentCoversItsTextPaddingAndBorder() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>a <span id="s">b</span> c</p>"#,
            rules: Self.baseRules + "#s { padding: 3px 6px; border: 2px solid red; }"
        )
        let span: ElementRef = try #require(page.firstElement(id: "s"))
        let line: LayoutID = try #require(try lines(page).first)
        let children: [LayoutID] = page.tree.childrenIDs(of: line)
        let widths: [CGFloat] = page.tree[line: line].content.inlineWidths
        let b: Int = try textChild(page, on: line, of: try spanText(page, "s"))
        let fragments: [InlineBoxFragment] = page.tree[line: line].inlineBoxes.fragments
        let font: BrowserFont = page.tree.font(children[b])
        let baseline: CGFloat = page.tree.ascent(line)

        #expect(fragments.count == 1)
        #expect(fragments.first?.dom == span.id)
        #expect(fragments.first?.opens == true)
        #expect(fragments.first?.closes == true)
        #expect(fragments.first?.rect == Rect(
            left: page.tree.x(children[b]) - 8 - page.tree.x(line),
            top: baseline - font.ascent - 5,
            right: page.tree.x(children[b]) + widths[b] - font.spaceWidth + 8 - page.tree.x(line),
            bottom: baseline + font.descent + 5
        ))
    }

    @Test func verticalPaddingDoesNotMakeTheLineTaller() throws {
        let plain: LayoutTestPage = LayoutTestPage(
            html: #"<p>a <span id="s">b</span> c</p>"#,
            rules: Self.baseRules
        )
        let padded: LayoutTestPage = LayoutTestPage(
            html: #"<p>a <span id="s">b</span> c</p>"#,
            rules: Self.baseRules + "#s { padding: 20px 0; border: 5px solid red; }"
        )

        let plainLine: LayoutID = try #require(try lines(plain).first)
        let paddedLine: LayoutID = try #require(try lines(padded).first)
        #expect(padded.tree.height(paddedLine) == plain.tree.height(plainLine))
    }

    @Test func wrappedSpanOpensOnItsFirstLineAndClosesOnItsLast() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>start <span id="s">one two three four five six seven eight nine ten</span> end</p>"#,
            rules: """
                html { width: 160px; }
                body { display: block; }
                p { display: block; }
                #s { padding: 0 10px; border: 1px solid red; }
                """
        )
        let span: ElementRef = try #require(page.firstElement(id: "s"))
        let spanLines: [[InlineBoxFragment]] = try lines(page)
            .map({ page.tree[line: $0].inlineBoxes.fragments.filter({ $0.dom == span.id }) })
            .filter({ !$0.isEmpty })

        #expect(spanLines.count > 2)
        #expect(spanLines.allSatisfy({ $0.count == 1 }))
        #expect(spanLines.first?.first?.opens == true)
        #expect(spanLines.first?.first?.closes == false)
        #expect(spanLines.last?.first?.opens == false)
        #expect(spanLines.last?.first?.closes == true)
        #expect(spanLines.dropFirst().dropLast().allSatisfy({ $0[0].opens == false && $0[0].closes == false }))
    }

    /// CSS 2.1 §8.6: in right-to-left text the element's start edges (its
    /// right padding and border) go on its first line, and its end edges
    /// (the left ones) on its last.
    @Test func rightToLeftSpanCarriesItsStartEdgesOnTheRight() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>start <span id="s">one two three four five six seven eight nine ten</span> end</p>"#,
            rules: """
                html { width: 160px; }
                body { display: block; }
                p { display: block; direction: rtl; }
                #s { padding: 0 10px; border-left: 2px solid red; border-right: 5px solid blue; }
                """
        )
        let span: ElementRef = try #require(page.firstElement(id: "s"))
        let text: NodeID = try spanText(page, "s")
        let owned: [LayoutID] = try lines(page).filter({ line in
            page.tree[line: line].inlineBoxes.fragments.contains(where: { $0.dom == span.id })
        })
        let first: LayoutID = try #require(owned.first)
        let last: LayoutID = try #require(owned.last)

        func spanPiece(on line: LayoutID) throws -> (fragment: InlineBoxFragment, text: LayoutID) {
            let fragment: InlineBoxFragment = try #require(page.tree[line: line].inlineBoxes.fragments.first)
            let child: LayoutID = try #require(page.tree.childrenIDs(of: line).first(where: { page.tree.domID(of: $0) == text }))
            return (fragment, child)
        }
        let opening: (fragment: InlineBoxFragment, text: LayoutID) = try spanPiece(on: first)
        let closing: (fragment: InlineBoxFragment, text: LayoutID) = try spanPiece(on: last)
        let index: Int = try textChild(page, on: first, of: text)
        let width: CGFloat = page.tree[line: first].content.inlineWidths[index]
        let space: CGFloat = page.tree.font(opening.text).spaceWidth

        #expect(owned.count > 2)
        #expect(page.tree.x(opening.text) == page.tree.x(first) + opening.fragment.rect.left)
        #expect(opening.fragment.rect.right == page.tree.x(opening.text) + width - space + 15 - page.tree.x(first))
        #expect(page.tree.x(closing.text) == page.tree.x(last) + closing.fragment.rect.left + 12)
    }

    @Test func gapsCountTowardLineBreaking() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><span id="s">one</span> two</p>"#,
            rules: Self.baseRules + "#s { padding-right: 590px; }"
        )

        #expect(try lines(page).count == 2)
    }

    @Test func spanWhoseFirstWordWrapsOpensOnTheNextLine() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>one two three four five <span id="s">six</span></p>"#,
            rules: """
                html { width: 160px; }
                body { display: block; }
                p { display: block; }
                #s { padding-left: 10px; border-left: 2px solid red; }
                """
        )
        let span: ElementRef = try #require(page.firstElement(id: "s"))
        let all: [LayoutID] = try lines(page)
        let owner: [LayoutID] = all.filter({ line in
            page.tree[line: line].inlineBoxes.fragments.contains(where: { $0.dom == span.id })
        })
        let text: NodeID = try spanText(page, "s")

        #expect(owner.count == 1)
        let line: LayoutID = try #require(owner.first)
        #expect(page.tree.childrenIDs(of: line).contains(where: { page.tree.domID(of: $0) == text }))
    }

    @Test func spanPaddingIsClickable() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>a <span id="s">b</span> c</p>"#,
            rules: Self.baseRules + "#s { padding: 0 20px; }"
        )
        let span: ElementRef = try #require(page.firstElement(id: "s"))
        let line: LayoutID = try #require(try lines(page).first)
        let fragment: InlineBoxFragment = try #require(page.tree[line: line].inlineBoxes.fragments.first)
        let x: CGFloat = page.tree.x(line) + fragment.rect.left + 2
        let y: CGFloat = page.tree.y(line) + (fragment.rect.top + fragment.rect.bottom) / 2

        #expect(page.tree.hitTest(page.tree.rootID, x: x, y: y)?.dom == span.id)
    }

    @Test func addingSpanPaddingRelaysOutIncrementally() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>a <span id="s">b</span> c</p>"#,
            rules: Self.baseRules
        )
        let span: ElementRef = try #require(page.firstElement(id: "s"))

        InlineStyle.set(span, property: "padding", value: "0 9px")
        InlineStyle.set(span, property: "border-left", value: "1px solid red")
        page.frame.setNeedsRender()
        page.frame.render()

        let line: LayoutID = try #require(try lines(page).first)
        let children: [LayoutID] = page.tree.childrenIDs(of: line)
        let widths: [CGFloat] = page.tree[line: line].content.inlineWidths
        let b: Int = try textChild(page, on: line, of: try spanText(page, "s"))
        #expect(page.tree.x(children[b]) == page.tree.x(children[b - 1]) + widths[b - 1] + 10)
        expectAllLayoutFieldsClean(try #require(page.frame.document))
        expectIncrementalMatchesFull(page)
    }

    @Test func turningASpanRightToLeftMovesItsEdgesIncrementally() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>start <span id="s">one two three four five six seven eight nine ten</span> end</p>"#,
            rules: """
                html { width: 160px; }
                body { display: block; }
                p { display: block; }
                #s { padding: 0 10px; border-left: 2px solid red; border-right: 5px solid blue; }
                """
        )
        let span: ElementRef = try #require(page.firstElement(id: "s"))
        let text: NodeID = try spanText(page, "s")

        InlineStyle.set(span, property: "direction", value: "rtl")
        page.frame.setNeedsRender()
        page.frame.render()

        let first: LayoutID = try #require(try lines(page).first(where: { line in
            page.tree[line: line].inlineBoxes.fragments.contains(where: { $0.dom == span.id })
        }))
        let fragment: InlineBoxFragment = try #require(page.tree[line: first].inlineBoxes.fragments.first)
        let child: LayoutID = try #require(page.tree.childrenIDs(of: first).first(where: { page.tree.domID(of: $0) == text }))
        #expect(page.tree.x(child) == page.tree.x(first) + fragment.rect.left)
        expectAllLayoutFieldsClean(try #require(page.frame.document))
        expectIncrementalMatchesFull(page)
    }
}

import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ScrollBoxTests {
    @Test func relayoutKeepsTheScrollPosition() throws {
        let page: LayoutTestPage = Self.makePage()
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let target: ScrollBlockTarget = try #require(page.frame.state.layout.targets.blocks.first)
        page.frame.scrollAt(x: target.rect.left + 5, y: target.rect.top + 5, deltaY: -10)

        page.frame.setViewport(width: 400, height: 600)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        #expect(box.scrollOffsetY == 10)
        #expect(Self.paintedScrollOffsets(page) == [10], "the relayout moved the box back")
    }

    @Test func scriptScrollTopIsPainted() throws {
        let page: LayoutTestPage = Self.makePage()
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        page.frame.js.run(
            script: "scrollTop",
            code: "document.getElementById('box').scrollTop = 25;"
        )

        #expect(Self.paintedScrollOffsets(page) == [25], "scrollTop did not reach the painted box")
    }

    @Test func offsetPastTheEndShowsTheEnd() throws {
        let page: LayoutTestPage = Self.makePage()
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        page.frame.js.run(
            script: "scrollTop",
            code: "document.getElementById('box').scrollTop = 100000;"
        )

        let id: LayoutID = try #require(box.ref.layoutID)
        let range: CGFloat = page.tree.blockContentHeight(id) - page.tree.height(id)
        #expect(range > 0)
        #expect(Self.paintedScrollOffsets(page) == [range])
    }

    @Test func hitTestFollowsTheScrollPosition() throws {
        let page: LayoutTestPage = Self.makePage()
        let target: ScrollBlockTarget = try #require(page.frame.state.layout.targets.blocks.first)
        let x: CGFloat = target.rect.left + 5
        let y: CGFloat = target.rect.top + 5
        page.frame.scrollAt(x: x, y: y, deltaY: -40)
        #expect(Self.paintedScrollOffsets(page) == [40])

        let shown: NodeID = try #require(Self.paragraph(in: page, containing: y + 40))
        #expect(Self.hitParagraph(page, x: x, y: y) == shown, "the click ignored the scroll position")
    }

    @Test func hitTestSkipsContentOutsideTheBox() throws {
        let page: LayoutTestPage = Self.makePage()
        let target: ScrollBlockTarget = try #require(page.frame.state.layout.targets.blocks.first)
        let x: CGFloat = target.rect.left + 5
        let below: CGFloat = target.rect.bottom + 5
        #expect(Self.paragraph(in: page, containing: below) != nil, "the content must overflow the box")

        #expect(Self.hitParagraph(page, x: x, y: below) == nil, "the click reached clipped content")
    }

    @Test func wheelOverABoxWithNothingToScrollMovesThePage() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><p>Short</p></div><div id="tall"></div>"#,
            rules: Self.chainRules
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let target: ScrollBlockTarget = try #require(page.frame.state.layout.targets.blocks.first)

        let moved: Bool = page.frame.scrollAt(x: target.rect.left + 5, y: target.rect.top + 5, deltaY: -40)

        #expect(moved)
        #expect(box.scrollOffsetY == 0)
        #expect(page.frame.scroll == 40, "the box swallowed the wheel")
    }

    @Test func wheelOverABoxAtItsEndMovesThePage() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">"# + Self.paragraphs + #"</div><div id="tall"></div>"#,
            rules: Self.chainRules
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let target: ScrollBlockTarget = try #require(page.frame.state.layout.targets.blocks.first)
        let x: CGFloat = target.rect.left + 5
        let y: CGFloat = target.rect.top + 5
        page.frame.scrollAt(x: x, y: y, deltaY: -100_000)
        let end: CGFloat = box.scrollOffsetY
        try #require(end > 0)
        try #require(page.frame.scroll == 0)

        page.frame.scrollAt(x: x, y: y, deltaY: -40)

        #expect(box.scrollOffsetY == end)
        #expect(page.frame.scroll == 40, "the box swallowed the wheel")
    }

    @Test func innerBoxScrollsBeforeTheBoxAroundIt() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="outer"><div id="inner">"# + Self.paragraphs + "</div>" + Self.paragraphs + "</div>",
            rules: Self.nestedRules
        )
        let outer: ElementRef = try #require(page.firstElement(id: "outer"))
        let inner: ElementRef = try #require(page.firstElement(id: "inner"))
        let target: ScrollBlockTarget = try #require(page.frame.state.layout.targets.blocks.last)
        try #require(target.node == inner.id)

        page.frame.scrollAt(x: target.rect.left + 5, y: target.rect.top + 5, deltaY: -10)

        #expect(inner.scrollOffsetY == 10)
        #expect(outer.scrollOffsetY == 0, "the outer box took the wheel meant for the inner one")
    }

    @Test func innerBoxWithNothingToScrollMovesTheBoxAroundIt() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="outer"><div id="inner"><p>Short</p></div>"# + Self.paragraphs + "</div>",
            rules: Self.nestedRules
        )
        let outer: ElementRef = try #require(page.firstElement(id: "outer"))
        let inner: ElementRef = try #require(page.firstElement(id: "inner"))
        let target: ScrollBlockTarget = try #require(page.frame.state.layout.targets.blocks.last)
        try #require(target.node == inner.id)

        page.frame.scrollAt(x: target.rect.left + 5, y: target.rect.top + 5, deltaY: -10)

        #expect(inner.scrollOffsetY == 0)
        #expect(outer.scrollOffsetY == 10)
        #expect(page.frame.scroll == 0)
    }

    @Test func pageAtItsTopKeepsTheWheelUnhandled() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><p>Short</p></div><div id="tall"></div>"#,
            rules: Self.chainRules
        )
        let target: ScrollBlockTarget = try #require(page.frame.state.layout.targets.blocks.first)

        let moved: Bool = page.frame.scrollAt(x: target.rect.left + 5, y: target.rect.top + 5, deltaY: 40)

        #expect(!moved)
        #expect(page.frame.scroll == 0)
    }

    // MARK: - Helpers

    private static let paragraphs: String = (0..<20).map { index in
        "<p>Paragraph \(index) inside the scroll box.</p>"
    }.joined()

    private static let chainRules: String = """
        body { display: block; }
        p { display: block; }
        div { display: block; }
        #box { height: 50px; overflow: scroll; }
        #tall { height: 2000px; }
        """

    private static let nestedRules: String = """
        body { display: block; }
        p { display: block; }
        div { display: block; }
        #outer { height: 100px; overflow: scroll; }
        #inner { height: 50px; overflow: scroll; }
        """

    private static func hitParagraph(_ page: LayoutTestPage, x: CGFloat, y: CGFloat) -> NodeID? {
        guard let hit: LayoutHit = page.tree.hitTest(page.tree.rootID, x: x, y: y) else { return nil }
        var node: DOMRef? = DOMRef(id: hit.dom, dom: page.frame.dom)
        while let current = node, current.element?.tag != "p" {
            node = current.parent
        }
        return node?.id
    }

    private static func paragraph(in page: LayoutTestPage, containing y: CGFloat) -> NodeID? {
        return treeToList(page.frame.nodes)
            .filter({ $0.element?.tag == "p" })
            .first(where: { node in
                guard let id: LayoutID = node.layoutID else { return false }
                let rect: Rect = page.tree.selfRect(id)
                return rect.top <= y && y < rect.bottom
            })?
            .id
    }

    private static func paintedScrollOffsets(_ page: LayoutTestPage) -> [CGFloat] {
        page.frame.setNeedsPaint()
        page.frame.paint()
        return page.frame.displayList.compactMap({ op in
            guard case .beginEffect(let scope) = op, case .scroll(_, let offset) = scope.kind else {
                return nil
            }
            return offset
        })
    }

    private static func makePage() -> LayoutTestPage {
        let paragraphs: String = (0..<20).map { index in
            "<p>Paragraph \(index) inside the scroll box.</p>"
        }.joined()
        return LayoutTestPage(
            html: #"<div id="box">"# + paragraphs + "</div>",
            rules: """
                body { display: block; }
                p { display: block; }
                div { display: block; height: 50px; overflow: scroll; }
                """
        )
    }
}

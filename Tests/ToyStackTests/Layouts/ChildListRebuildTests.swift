import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ChildListRebuildTests {
    private let css: String = """
        body { display: block; }
        div { display: block; }
        p { display: block; }
        h6 { display: block; }
    """

    @Test func hidingASiblingKeepsTheOtherBlocks() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><div id="a">gone</div><p id="b">one two</p><p id="c">three</p></div>"#,
            rules: css
        )
        let before: [LayoutID] = try blockIDs(["b", "c"], in: page)

        profiler.reset()
        try setDisplay("none", of: "a", in: page)

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(metrics["layout.children.rebuilt"]?.count == 1)
        #expect(metrics["layout.inline.refresh"] == nil)
        #expect(try blockIDs(["b", "c"], in: page) == before)
        expectIncrementalMatchesFull(page)
    }

    @Test func showingAHiddenSiblingKeepsTheOtherBlocks() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><div id="a" style="display:none">back</div><p id="b">one two</p><p id="c">three</p></div>"#,
            rules: css
        )
        let before: [LayoutID] = try blockIDs(["b", "c"], in: page)

        try setDisplay("block", of: "a", in: page)

        #expect(try blockIDs(["b", "c"], in: page) == before)
        expectIncrementalMatchesFull(page)
    }

    @Test func anonymousBlockWithTheSameContentIsKept() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">loose <b>bold</b><div id="a">gone</div><p id="c">three</p></div>"#,
            rules: css
        )
        let box: LayoutID = try blockID("box", in: page)
        let anonymous: LayoutID = try #require(page.tree.childrenIDs(of: box).first)

        try setDisplay("none", of: "a", in: page)

        #expect(page.tree.childrenIDs(of: box).first == anonymous)
        expectIncrementalMatchesFull(page)
    }

    @Test func anonymousBlockWhoseContentChangedIsRebuilt() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">loose <b id="s">bold</b><div id="a">x</div></div>"#,
            rules: css
        )
        let box: LayoutID = try blockID("box", in: page)
        let anonymous: LayoutID = try #require(page.tree.childrenIDs(of: box).first)

        try setDisplay("none", of: "s", in: page)

        #expect(page.tree.childrenIDs(of: box).first != anonymous)
        expectIncrementalMatchesFull(page)
    }

    @Test func textTypedAfterABlockChildShowsUp() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<div id=\"box\"><p>para</p> </div>",
            rules: css
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let trailing: TextRef = try #require(box.children.last?.text)

        trailing.append("typed")
        page.frame.setNeedsStyle(box.ref)
        page.frame.render()

        let texts: [String] = treeToList(page.tree, page.tree.rootID)
            .filter({ page.tree.isText($0) })
            .map({ page.tree.textString($0) })
        #expect(texts.contains("typed"))
        expectIncrementalMatchesFull(page)
    }

    @Test func blockThatTurnsInlineJoinsARunAndTheRestAreKept() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><p id="b">one</p><p id="c">two</p><p id="d">three</p></div>"#,
            rules: css
        )
        let kept: [LayoutID] = try blockIDs(["c", "d"], in: page)

        try setDisplay("inline", of: "b", in: page)

        let box: LayoutID = try blockID("box", in: page)
        #expect(Array(page.tree.childrenIDs(of: box).suffix(2)) == kept)
        expectIncrementalMatchesFull(page)
    }

    @Test func runInHeadingKeepsItsPairedBlock() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><div id="a">gone</div><h6>Run</h6><p>in text</p><p id="c">after</p></div>"#,
            rules: css
        )
        let box: LayoutID = try blockID("box", in: page)
        let runIn: LayoutID = page.tree.childrenIDs(of: box)[1]

        try setDisplay("none", of: "a", in: page)

        #expect(page.tree.childrenIDs(of: box).first == runIn)
        expectIncrementalMatchesFull(page)
    }

    @Test func keptBlocksBesideAFloatStillWrapAroundIt() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="box"><div id="a">gone</div><div id="f"></div>\
                <p id="b">one two three four five six seven eight nine ten</p></div>
                """,
            rules: css + "#f { float: left; width: 100px; height: 80px; } #box { width: 300px; }"
        )
        let before: [LayoutID] = try blockIDs(["f", "b"], in: page)

        try setDisplay("none", of: "a", in: page)

        #expect(try blockIDs(["f", "b"], in: page) == before)
        expectIncrementalMatchesFull(page)
    }

    // MARK: - Helpers

    private func setDisplay(_ value: String, of id: String, in page: LayoutTestPage) throws {
        let element: ElementRef = try #require(page.firstElement(id: id))
        InlineStyle.set(element, property: "display", value: value)
        page.frame.setNeedsStyleSubtree(element.ref)
        page.frame.render()
    }

    private func blockID(_ id: String, in page: LayoutTestPage) throws -> LayoutID {
        let element: ElementRef = try #require(page.firstElement(id: id))
        return try #require(page.tree.primaryLayout(for: element.ref.id))
    }

    private func blockIDs(_ ids: [String], in page: LayoutTestPage) throws -> [LayoutID] {
        return try ids.map({ try blockID($0, in: page) })
    }
}

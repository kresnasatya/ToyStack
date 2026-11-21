import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct StyleSnapshotCacheTests {
    @Test func attributeMutationInvalidatesCachedSnapshot() throws {
        let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 800)
        let frame: Frame = tab.rootFrame
        let dom: DOMTree = HTMLParser(body: #"<div id="target" class="old">x</div>"#).parse()
        frame.replaceDOM(dom)
        frame.setStyleRules(CSSParser("""
            div.old { color: red; }
            div.new { color: blue; }
            """).parse().rules)
        frame.setNeedsRender()
        frame.render()

        let target: ElementRef = try #require(
            treeToList(dom.ref(dom.root)).compactMap(\.element)
                .first(where: { $0.attributes["id"] == "target" })
        )
        #expect(target.style.computed.text.color == BrowserColor(cssName: "red"))

        dom.setAttribute("class", "new", of: target.ref.id)
        frame.setNeedsStyle(target.ref)
        frame.render()

        #expect(target.style.computed.text.color == BrowserColor(cssName: "blue"))
    }

    @Test func updatedSnapshotMatchesAFreshBuildAfterEveryKindOfChange() throws {
        let dom: DOMTree = HTMLParser(body: #"<div id="box" class="a"><p>one</p><p>two</p></div>"#).parse()
        var snapshot: StyleSnapshot = StyleSnapshotBuilder.build(dom: dom)
        let box: NodeID = try #require(
            treeToList(dom.ref(dom.root)).compactMap(\.element)
                .first(where: { $0.attributes["id"] == "box" })?.ref.id
        )
        let firstParagraph: NodeID = try #require(dom.children(of: box).first)
        let firstText: NodeID = try #require(dom.children(of: firstParagraph).first)

        dom.setAttribute("class", "b", of: box)
        dom.setText("changed", of: firstText)
        dom.setFlag(\.isHovered, true, of: firstParagraph)
        dom.setSatisfiedHas([3], of: box)
        let added: NodeID = dom.createElement(tag: "span", attributes: ["title": "new"])
        dom.append(added, to: firstParagraph)
        dom.append(dom.createText("tail"), to: added)
        StyleSnapshotBuilder.update(&snapshot, dom: dom)

        let fresh: StyleSnapshot = StyleSnapshotBuilder.build(dom: dom)
        #expect(snapshot.nodes.count == fresh.nodes.count)
        for (index, expected) in fresh.nodes.enumerated() {
            let expected: StyleNode = try #require(expected)
            let actual: StyleNode = snapshot.node(try #require(snapshot.index(of: expected.identity.id)))
            #expect(actual.content.tag == expected.content.tag, "node \(index)")
            #expect(actual.content.attributes == expected.content.attributes, "node \(index)")
            #expect(actual.content.text == expected.content.text, "node \(index)")
            #expect(actual.identity.parent == expected.identity.parent, "node \(index)")
            #expect(actual.identity.children == expected.identity.children, "node \(index)")
            #expect(actual.state.isHovered == expected.state.isHovered, "node \(index)")
            #expect(actual.state.satisfiedHas == expected.state.satisfiedHas, "node \(index)")
        }
    }

    @Test func textEditUpdatesOneSnapshotNode() throws {
        let html: String = (0..<20).map({ "<p id=\"p\($0)\">paragraph \($0)</p>" }).joined()
        let page: LayoutTestPage = LayoutTestPage(
            html: html,
            rules: "body { display: block; } p { display: block; } p:hover { color: red; }"
        )
        let paragraph: ElementRef = try #require(page.firstElement(id: "p7"))
        let text: TextRef = try #require(paragraph.children.first?.text)
        page.frame.setNeedsStyle(paragraph.ref)
        page.frame.render()

        text.append(" more")
        page.frame.setNeedsStyle(paragraph.ref)
        // The layout phase resets the profiler; this test only observes style.
        page.frame.state.layout.tree.isDirty = false
        profiler.reset()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(metrics["style.snapshot.nodes.updated"]?.count == 1)
        #expect(metrics["style.snapshot.build"] == nil)
    }
}

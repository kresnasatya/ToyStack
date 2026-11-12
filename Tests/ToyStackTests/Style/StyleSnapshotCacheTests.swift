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
}

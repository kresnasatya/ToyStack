import Testing

@testable import Engine

// The two scripts are copied unchanged from a Next.js page (palm-co.de). React
// streams a placeholder first, then the real section in a hidden div, and these
// scripts move the real section into place.
@Suite(.serialized)
@MainActor
struct StreamedSectionSwapTests {
    private let completeBoundary: String = #"""
        $RC=function(b,c,e){c=document.getElementById(c);c.parentNode.removeChild(c);var a=document.getElementById(b);if(a){b=a.previousSibling;if(e)b.data="$!",a.setAttribute("data-dgst",e);else{e=b.parentNode;a=b.nextSibling;var f=0;do{if(a&&8===a.nodeType){var d=a.data;if("/$"===d)if(0===f)break;else f--;else"$"!==d&&"$?"!==d&&"$!"!==d||f++}d=a.nextSibling;e.removeChild(a);a=d}while(a);for(;c.firstChild;)e.insertBefore(c.firstChild,a);b.data="$"}b._reactRetry&&b._reactRetry()}};
        """#

    private let completeSegment: String = #"""
        $RS=function(a,b){a=document.getElementById(a);b=document.getElementById(b);for(a.parentNode.removeChild(a);a.firstChild;)b.parentNode.insertBefore(a.firstChild,b);b.parentNode.removeChild(b)};
        """#

    private let css: String = """
        body { display: block; }
        div { display: block; }
        p { display: block; }
    """

    private func childDescriptions(_ page: LayoutTestPage, of id: String) throws -> [String] {
        let element: ElementRef = try #require(page.firstElement(id: id))
        return page.frame.dom.children(of: element.ref.id).map({ page.frame.dom.ref($0).description })
    }

    @Test func boundarySwapReplacesPlaceholderWithStreamedSection() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="root"><!--$?--><template id="B:0"></template><p id="fallback">Loading</p><!--/$--><p id="after">after</p></div><div hidden id="S:0"><p id="real">Real</p><!-- -->text</div>"#,
            rules: css
        )
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        page.frame.js.run(script: "inline", code: completeBoundary + #"$RC("B:0","S:0")"#)
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(try childDescriptions(page, of: "root") == ["<!--$-->", "<p>", "<!-- -->", "\"text\"", "<!--/$-->", "<p>"])
        #expect(page.firstElement(id: "real") != nil)
        #expect(page.firstElement(id: "fallback") == nil)
        #expect(page.firstElement(id: "S:0") == nil)
        #expect(page.firstElement(id: "B:0") == nil)
        expectIncrementalMatchesFull(page)
    }

    @Test func boundarySwapStopsAtItsOwnEndMarker() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="root"><!--$?--><template id="B:1"></template><!--$--><p>inner done</p><!--/$--><p id="fallback">Loading</p><!--/$--><p id="after">after</p></div><div hidden id="S:1"><p id="real">Real</p></div>"#,
            rules: css
        )
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        page.frame.js.run(script: "inline", code: completeBoundary + #"$RC("B:1","S:1")"#)
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(try childDescriptions(page, of: "root") == ["<!--$-->", "<p>", "<!--/$-->", "<p>"])
        #expect(page.firstElement(id: "after") != nil)
        expectIncrementalMatchesFull(page)
    }

    @Test func segmentSwapReplacesPlaceholderTemplate() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="root"><template id="P:3"></template><p id="after">after</p></div><div hidden id="S:3"><p id="segment">Segment</p></div>"#,
            rules: css
        )
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        page.frame.js.run(script: "inline", code: completeSegment + #"$RS("S:3","P:3")"#)
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(try childDescriptions(page, of: "root") == ["<p>", "<p>"])
        #expect(page.firstElement(id: "segment") != nil)
        #expect(page.firstElement(id: "P:3") == nil)
        #expect(page.firstElement(id: "S:3") == nil)
        expectIncrementalMatchesFull(page)
    }
}

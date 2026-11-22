import JavaScriptCore
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct NodeTraversalTests {
    private let css: String = """
        body { display: block; }
        div { display: block; }
        p { display: block; }
    """

    private func makePage(_ html: String) -> LayoutTestPage {
        let page: LayoutTestPage = LayoutTestPage(html: html, rules: css)
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        return page
    }

    @Test func childrenWalkIncludesTextAndComments() {
        let page: LayoutTestPage = makePage(#"<div id="box">a<!--m--><p id="last">b</p></div>"#)
        let result: JSValue? = page.frame.js.evaluate("""
            var box = document.getElementById('box');
            var text = box.firstChild;
            var comment = text.nextSibling;
            var last = comment.nextSibling;
            [
                box.nodeType, text.nodeType, text.data, comment.nodeType, comment.data,
                last.getAttribute('id'), last.previousSibling.data,
                last.nextSibling === null, text.previousSibling === null,
                comment.parentNode.getAttribute('id')
            ].join(',')
        """)
        #expect(result?.toString() == "1,3,a,8,m,last,m,true,true,box")
    }

    @Test func emptyAndDetachedNodesWalkToNull() {
        let page: LayoutTestPage = makePage(#"<div id="box"></div>"#)
        let result: JSValue? = page.frame.js.evaluate("""
            var box = document.getElementById('box');
            var loose = document.createElement('p');
            [
                box.firstChild === null, loose.parentNode === null,
                loose.previousSibling === null, loose.nextSibling === null
            ].join(',')
        """)
        #expect(result?.toString() == "true,true,true,true")
    }

    @Test func settingCommentDataShowsInMarkupButNotOnScreen() throws {
        let page: LayoutTestPage = makePage(#"<div id="box"><!--$?--><p>shown</p></div>"#)
        page.frame.js.run(script: "data", code: "document.getElementById('box').firstChild.data = '$'")
        page.frame.setNeedsRender()
        page.frame.render()

        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let marker: NodeID = page.frame.dom.children(of: box.ref.id)[0]
        #expect(page.frame.dom.comment(marker)?.data == "$")
        let markup: JSValue? = page.frame.js.evaluate("document.getElementById('box').innerHTML")
        #expect(markup?.toString() == "<!--$--><p>shown</p>")
        expectIncrementalMatchesFull(page)
    }

    @Test func settingTextDataUpdatesTheRenderedText() throws {
        let page: LayoutTestPage = makePage(#"<div id="box"><p id="p">old</p></div>"#)
        let p: ElementRef = try #require(page.firstElement(id: "p"))
        let widthBefore: CGFloat = page.textWidthID(in: p)

        page.frame.js.run(script: "data", code: "document.getElementById('p').firstChild.data = 'changed text'")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(page.frame.dom.text(page.frame.dom.children(of: p.ref.id)[0])?.text == "changed text")
        #expect(page.textWidthID(in: p) > widthBefore)
        expectIncrementalMatchesFull(page)
    }

    @Test func documentElementIsTheRootWithNoParent() {
        let page: LayoutTestPage = makePage(#"<html lang="en"><body><p>x</p></body></html>"#)
        let result: JSValue? = page.frame.js.evaluate("""
            var root = document.documentElement;
            [root.getAttribute('lang'), root.parentNode === null].join('|')
        """)
        #expect(result?.toString() == "en|true")
    }

    @Test func childNodesListsTextAndCommentsButChildrenDoesNot() {
        let page: LayoutTestPage = makePage(#"<div id="box">a<!--m--><p>b</p></div>"#)
        let result: JSValue? = page.frame.js.evaluate("""
            var box = document.getElementById('box');
            [box.childNodes.map(function (n) { return n.nodeType; }).join(''), box.children.length].join('|')
        """)
        #expect(result?.toString() == "381|1")
    }
}

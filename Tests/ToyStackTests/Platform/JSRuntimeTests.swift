import JavaScriptCore
import Testing

@testable import Engine

@Suite
@MainActor
struct JSRuntimeTests {
    @Test func windowLocationIsTheLocationObject() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<h1 id=header>Header</h1>",
            rules: "body { display: block; }"
        )
        let js: JSRuntime = JSRuntime(frame: page.frame)
        let result: JSValue? = js.evaluate("window.location === location")
        #expect(result?.toBool() == true)
    }

    @Test func selfAndWindowAreTheGlobalObject() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>x</p>", rules: "")
        let js: JSRuntime = JSRuntime(frame: page.frame)
        let result: JSValue? = js.evaluate("self === window && window === globalThis && window.window === window")
        #expect(result?.toBool() == true)
    }

    @Test func propertySetThroughSelfIsSeenByLaterScripts() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>x</p>", rules: "")
        let js: JSRuntime = JSRuntime(frame: page.frame)
        js.run(script: "bootstrap", code: "(self.__next_f = self.__next_f || []).push([0])")
        js.run(script: "inline", code: "self.__next_f.push([1, \"chunk\"])")
        let result: JSValue? = js.evaluate("__next_f.length")
        #expect(result?.toInt32() == 2)
    }

    @Test func windowStillReceivesPostedMessages() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>x</p>", rules: "")
        let js: JSRuntime = JSRuntime(frame: page.frame)
        js.run(script: "listener", code: "var got = null; window.addEventListener('message', function (e) { got = e.data; })")
        js.dispatchPostMessage(message: "hello")
        let result: JSValue? = js.evaluate("got")
        #expect(result?.toString() == "hello")
    }

    @Test func topWindowHasNoParent() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>x</p>", rules: "")
        let js: JSRuntime = JSRuntime(frame: page.frame)
        let result: JSValue? = js.evaluate("window.parent === undefined")
        #expect(result?.toBool() == true)
    }

    @Test func currentScriptIsTheRunningScriptAndNullAfterward() throws {
        let page: LayoutTestPage = LayoutTestPage(html: #"<script id="s"></script><p>x</p>"#, rules: "")
        let js: JSRuntime = JSRuntime(frame: page.frame)
        let script: ElementRef = try #require(page.firstElement(id: "s"))
        js.run(script: "inline", code: "var seen = document.currentScript.id", element: script.id)
        js.run(script: "setTimeout", code: "var later = document.currentScript")
        let result: JSValue? = js.evaluate("[seen, later === null, document.currentScript === null].join('|')")
        #expect(result?.toString() == "s|true|true")
    }

    @Test func documentScriptsListsScriptsInTreeOrder() {
        let page: LayoutTestPage = LayoutTestPage(html: #"<script id="a"></script><p>x</p><script id="b"></script>"#, rules: "")
        let js: JSRuntime = JSRuntime(frame: page.frame)
        let result: JSValue? = js.evaluate("document.scripts.map(function (s) { return s.id; }).join(',') + '|' + document.scripts.length")
        #expect(result?.toString() == "a,b|2")
    }

    @Test func linkHrefIsResolvedAgainstThePage() {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<a id="rel" href="../about">a</a><a id="mail" href="mailto:me@example.com">m</a><a id="none">n</a>"#,
            rules: ""
        )
        page.frame.setURL(WebURL("https://example.com/blog/post"))
        let js: JSRuntime = JSRuntime(frame: page.frame)
        let result: JSValue? = js.evaluate("""
            ['rel', 'mail', 'none'].map(function (id) { return document.getElementById(id).href; }).join('|')
        """)
        #expect(result?.toString() == "https://example.com/about|mailto:me@example.com|")
    }

    @Test func settingHrefWritesTheAttribute() {
        let page: LayoutTestPage = LayoutTestPage(html: #"<a id="a" href="/x">a</a>"#, rules: "")
        let js: JSRuntime = JSRuntime(frame: page.frame)
        let result: JSValue? = js.evaluate("""
            var a = document.getElementById('a');
            a.href = 'mailto:me@example.com';
            [a.getAttribute('href'), a.hasAttribute('href'), a.hasAttribute('title')].join('|')
        """)
        #expect(result?.toString() == "mailto:me@example.com|true|false")
    }
}

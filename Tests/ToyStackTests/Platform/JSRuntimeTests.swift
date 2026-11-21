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
}

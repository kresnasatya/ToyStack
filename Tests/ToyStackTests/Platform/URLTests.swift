import JavaScriptCore
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct URLTests {
    private func makeRuntime() -> JSRuntime {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>x</p>", rules: "")
        return JSRuntime(frame: page.frame)
    }

    @Test func relativeURLResolvesAgainstTheBase() {
        let js: JSRuntime = makeRuntime()
        let result: JSValue? = js.evaluate("""
            var u = new URL('../img/a.png?w=2#top', 'https://example.com:8443/blog/post/');
            [u.href, u.protocol, u.host, u.hostname, u.port, u.pathname, u.search, u.hash, u.origin].join('|')
        """)
        #expect(result?.toString() == "https://example.com:8443/blog/img/a.png?w=2#top|https:|example.com:8443|example.com|8443|/blog/img/a.png|?w=2|#top|https://example.com:8443")
    }

    @Test func defaultPortIsLeftOut() {
        let js: JSRuntime = makeRuntime()
        let result: JSValue? = js.evaluate("var u = new URL('https://example.com/'); [u.host, u.port, u.origin, String(u)].join('|')")
        #expect(result?.toString() == "example.com||https://example.com|https://example.com/")
    }

    @Test func absoluteInputIgnoresTheBase() {
        let js: JSRuntime = makeRuntime()
        let result: JSValue? = js.evaluate("new URL('https://cdn.example.net/x.js', 'https://example.com/a/').href")
        #expect(result?.toString() == "https://cdn.example.net/x.js")
    }

    @Test func unparseableInputThrowsTypeError() {
        let js: JSRuntime = makeRuntime()
        let result: JSValue? = js.evaluate("""
            var names = [];
            try { new URL('not a url'); } catch (e) { names.push(e instanceof TypeError); }
            try { new URL('/a', 'also not a url'); } catch (e) { names.push(e instanceof TypeError); }
            names.join('|')
        """)
        #expect(result?.toString() == "true|true")
    }

    // Turbopack's runtime reads URL.prototype on its first line and copies a URL's own
    // fields with for...in.
    @Test func turbopackCanSubclassAndCopyAURL() {
        let js: JSRuntime = makeRuntime()
        let result: JSValue? = js.evaluate("""
            var R = function () {}; R.prototype = URL.prototype;
            var copied = [];
            for (var key in new URL('https://example.com/a')) copied.push(key);
            [new R() instanceof URL, copied.indexOf('href') !== -1, copied.indexOf('pathname') !== -1].join('|')
        """)
        #expect(result?.toString() == "true|true|true")
    }
}

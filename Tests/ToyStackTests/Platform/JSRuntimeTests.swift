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
}

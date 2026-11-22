import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct CanvasBackgroundTests {
    private let dark: BrowserColor = BrowserColor(red: 10 / 255, green: 10 / 255, blue: 10 / 255)

    private func canvas(_ html: String, _ css: String) -> BrowserColor? {
        let page: LayoutTestPage = LayoutTestPage(html: html, rules: "body { display: block; } " + css)
        return CanvasBackground.color(of: page.frame.nodes)
    }

    // CSS Backgrounds 3 §2.11.2: when <html> has no background, the canvas takes the
    // background of <body>.
    @Test func bodyBackgroundFillsTheCanvas() {
        #expect(canvas("<p>x</p>", "body { background-color: rgb(10 10 10); }") == dark)
    }

    // CSS Backgrounds 3 §2.11.1: the root element's own background wins over the body's.
    @Test func rootBackgroundWinsOverBody() {
        let color: BrowserColor? = canvas(
            "<p>x</p>",
            "html { background-color: red; } body { background-color: rgb(10 10 10); }"
        )
        #expect(color == BrowserColor(cssName: "red"))
    }

    @Test func fullyTransparentRootPassesToBody() {
        let color: BrowserColor? = canvas(
            "<p>x</p>",
            "html { background-color: rgba(255, 0, 0, 0); } body { background-color: rgb(10 10 10); }"
        )
        #expect(color == dark)
    }

    @Test func noBackgroundAnywhereLeavesTheCanvasToTheBrowser() {
        #expect(canvas("<p>x</p>", "p { background-color: red; }") == nil)
        #expect(canvas("<p>x</p>", "body { background-color: transparent; }") == nil)
    }
}

import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct MediaQueryParsingTests {
    private func page(_ rules: String) -> LayoutTestPage {
        return LayoutTestPage(
            html: #"<nav id="toc">contents</nav><p id="x">text</p><em id="y">more</em>"#,
            rules: "body { display: block; } p { display: block; } " + rules
        )
    }

    private func display(_ page: LayoutTestPage, _ id: String) throws -> LayoutStyle.Display {
        let element: ElementRef = try #require(page.firstElement(id: id))
        return element.style.computed.layout.display
    }

    private func color(_ page: LayoutTestPage, _ id: String) throws -> BrowserColor {
        let element: ElementRef = try #require(page.firstElement(id: id))
        return element.style.computed.text.color
    }

    @Test func onlyScreenWidthQueryAppliesWhenWideEnough() throws {
        let page: LayoutTestPage = page("""
            nav#toc { display: none; }
            @media only screen and (min-width: 700px) { nav#toc { display: block; } }
            """)
        #expect(try display(page, "toc") == .block)
    }

    @Test func onlyScreenWidthQueryStaysOffWhenTooNarrow() throws {
        let page: LayoutTestPage = page("""
            nav#toc { display: none; }
            @media only screen and (min-width: 1150px) { nav#toc { display: block; } }
            """)
        #expect(try display(page, "toc") == LayoutStyle.Display.none)
    }

    @Test func onlyScreenWidthQueryTurnsOnAfterWindowGrows() throws {
        let page: LayoutTestPage = page("""
            nav#toc { display: none; }
            @media only screen and (min-width: 1150px) { nav#toc { display: block; } }
            """)
        page.frame.setViewport(width: 1200, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()
        #expect(try display(page, "toc") == .block)
    }

    @Test func screenTypeWithoutFeatureAlwaysApplies() throws {
        let page: LayoutTestPage = page("@media screen { p { color: blue; } }")
        #expect(try color(page, "x") == BrowserColor.parse("blue"))
    }

    @Test func printBlockNeverApplies() throws {
        let page: LayoutTestPage = page("""
            p { color: red; }
            @media print { p { color: blue; } }
            @media only print and (min-width: 1px) { p { color: green; } }
            """)
        #expect(try color(page, "x") == BrowserColor.parse("red"))
    }

    @Test func queryMissingAndDropsOnlyItsOwnBlock() throws {
        let page: LayoutTestPage = page("""
            p { color: red; }
            @media only screen (min-width: 1px) { p { color: blue; } }
            em { color: green; }
            """)
        #expect(try color(page, "x") == BrowserColor.parse("red"))
        #expect(try color(page, "y") == BrowserColor.parse("green"))
    }
}

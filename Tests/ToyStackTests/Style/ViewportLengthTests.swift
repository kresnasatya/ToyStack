import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ViewportLengthTests {
    private func page(_ rules: String) -> LayoutTestPage {
        return LayoutTestPage(
            html: #"<div id="outer"><div id="x">text</div></div>"#,
            rules: "body { display: block; } div { display: block; } " + rules
        )
    }

    private func style(_ page: LayoutTestPage) throws -> ComputedStyle {
        let element: ElementRef = try #require(page.firstElement(id: "x"))
        return element.style.computed
    }

    private func resize(_ page: LayoutTestPage, width: CGFloat, height: CGFloat) {
        page.frame.setViewport(width: width, height: height)
        page.frame.setNeedsViewportResize()
        page.frame.render()
    }

    @Test func vwAndVhAreAPercentOfTheViewport() throws {
        let style: ComputedStyle = try style(page("""
            #x { width: 50vw; height: 25vh; margin-left: 10vw; font-size: 4vh; }
            """))
        #expect(style.box.size.width == 400)
        #expect(style.box.size.height == 150)
        #expect(style.box.spacing.margin.left == 80)
        #expect(style.text.font.size == 24)
    }

    @Test func viewportLengthsFollowAResize() throws {
        let page: LayoutTestPage = page("#x { width: 50vw; height: 25vh; }")
        resize(page, width: 400, height: 300)
        #expect(try style(page).box.size.width == 200)
        #expect(try style(page).box.size.height == 75)
    }

    @Test func vhFollowsAHeightOnlyResize() throws {
        let page: LayoutTestPage = page("#x { height: 50vh; }")
        resize(page, width: page.frame.frameWidth, height: 200)
        #expect(try style(page).box.size.height == 100)
    }

    @Test func inheritedFontSizeInVwFollowsAResize() throws {
        let page: LayoutTestPage = page("#outer { font-size: 2vw; } #x { margin-left: 2em; }")
        #expect(try style(page).box.spacing.margin.left == 32)
        resize(page, width: 400, height: page.frame.frameHeight)
        #expect(try style(page).text.font.size == 8)
        #expect(try style(page).box.spacing.margin.left == 16)
    }

    @Test func pageZoomShrinksTheViewportInCSSPixels() throws {
        let page: LayoutTestPage = page("#x { width: 50vw; }")
        page.frame.setPageZoom(2)
        page.frame.render()
        #expect(try style(page).box.size.width == 200)
    }
}

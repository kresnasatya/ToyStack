import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct UserAgentButtonStyleTests {
    private func page(prefersDark: Bool) -> LayoutTestPage {
        let page: LayoutTestPage = LayoutTestPage(html: #"<p><button id="go">Go</button></p>"#, rules: "")
        page.tab.prefersDark = prefersDark
        page.frame.setStyleRules(defaultStyleSheet + CSSParser("html { width: 600px; }").parse().rules)
        page.frame.setNeedsRender()
        page.frame.render()
        return page
    }

    private func sides(_ style: ComputedStyle) -> [BoxStyle.Decoration.Border.Side] {
        let sides: BoxStyle.Decoration.Border.Sides = style.box.decoration.border.sides
        return [sides.top, sides.right, sides.bottom, sides.left]
    }

    @Test func buttonHasTheLightGrayFaceAndThinGrayBorderOfRealBrowsers() throws {
        let page: LayoutTestPage = page(prefersDark: false)
        let style: ComputedStyle = try #require(page.firstElement(id: "go")).style.computed

        #expect(style.visual.background.color == BrowserColor(cssName: "#efefef"))
        #expect(style.text.color == BrowserColor(cssName: "black"))
        for side in sides(style) {
            #expect(side.width == 1)
            #expect(side.style == .solid)
            #expect(side.color == BrowserColor(cssName: "#767676"))
        }
        #expect(style.box.decoration.border.radii == .uniform(.px(2)))
    }

    /// Real browsers give a button 2px of border plus 1px/6px of padding but
    /// paint only a 1px ring, so 1px border plus 2px/7px padding keeps the
    /// same size and the same look.
    @Test func buttonHasTheSizeOfRealBrowsers() throws {
        let page: LayoutTestPage = page(prefersDark: false)
        let style: ComputedStyle = try #require(page.firstElement(id: "go")).style.computed

        #expect(style.box.spacing.padding == EdgeInsets(top: 2, right: 7, bottom: 2, left: 7))
        #expect(style.box.paddingAndBorder == EdgeInsets(top: 3, right: 8, bottom: 3, left: 8))
        #expect(abs(style.text.font.size - 13.333) < 0.001)
    }

    @Test func darkSchemeButtonHasTheDarkGrayFaceAndWhiteText() throws {
        let page: LayoutTestPage = page(prefersDark: true)
        let style: ComputedStyle = try #require(page.firstElement(id: "go")).style.computed

        #expect(style.visual.background.color == BrowserColor(cssName: "#6b6b6b"))
        #expect(style.text.color == BrowserColor(cssName: "white"))
        for side in sides(style) {
            #expect(side.width == 1)
            #expect(side.color == BrowserColor(cssName: "#6b6b6b"))
        }
    }
}

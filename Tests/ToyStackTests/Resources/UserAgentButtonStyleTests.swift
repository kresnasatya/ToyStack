import CoreGraphics
import CoreText
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct UserAgentButtonStyleTests {
    private func page(prefersDark: Bool) -> LayoutTestPage {
        let page: LayoutTestPage = LayoutTestPage(html: #"<p>Before <button id="go">Go</button></p>"#, rules: "")
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

    @Test func buttonHasTheSizeOfRealBrowsers() throws {
        let page: LayoutTestPage = page(prefersDark: false)
        let style: ComputedStyle = try #require(page.firstElement(id: "go")).style.computed

        #expect(style.box.spacing.padding == EdgeInsets(top: 2, right: 7, bottom: 2, left: 7))
        #expect(style.box.paddingAndBorder == EdgeInsets(top: 3, right: 8, bottom: 3, left: 8))
        #expect(abs(style.text.font.size - 13.333) < 0.001)
    }

    private func familyName(_ font: BrowserFont) -> String {
        return CTFontCopyFamilyName(font.ctFont) as String
    }

    /// CSS Fonts 4 §2.1.5: `system-ui` renders text in the default user interface font,
    /// the one Safari and Firefox on macOS give a button's label.
    @Test func labelUsesTheSystemFontWhileTheParagraphKeepsItsOwn() throws {
        let page: LayoutTestPage = page(prefersDark: false)
        let element: ElementRef = try #require(page.firstElement(id: "go"))
        let button: LayoutID = try #require(page.embedID(in: element, .button))
        let line: LayoutID = try #require(page.tree.childrenIDs(of: button).first)
        let label: LayoutID = try #require(page.tree.childrenIDs(of: line).first)
        let paragraph: ElementRef = try #require(page.firstElement(tag: "p"))
        let before: LayoutID = try #require(page.firstLayoutID(in: paragraph, where: { id, tree in
            tree.isText(id) && tree.textString(id) == "Before"
        }))
        let system: CTFont = try #require(CTFontCreateUIFontForLanguage(.system, 13, nil))

        #expect(element.style.computed.text.font.family == "system-ui")
        #expect(familyName(page.tree.font(label)) == CTFontCopyFamilyName(system) as String)
        #expect(familyName(page.tree.font(before)) == "Georgia")
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

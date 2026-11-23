import CoreGraphics
import CoreText
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct FontRelativeLengthTests {
    private func box(_ rules: String) throws -> ComputedStyle {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="outer"><div id="x">text</div></div>"#,
            rules: "body { display: block; } div { display: block; } " + rules
        )
        let element: ElementRef = try #require(page.firstElement(id: "x"))
        return element.style.computed
    }

    @Test func emFollowsTheElementsOwnFontSize() throws {
        let style: ComputedStyle = try box("""
            #outer { font-size: 10px; }
            #x { font-size: 20px; width: 10em; margin-left: 1em; padding-top: 0.5em; }
            """)
        #expect(style.box.size.width == 200)
        #expect(style.box.spacing.margin.left == 20)
        #expect(style.box.spacing.padding.top == 10)
    }

    @Test func fontSizeInEmFollowsTheParentFontSize() throws {
        let style: ComputedStyle = try box("#outer { font-size: 10px; } #x { font-size: 2em; }")
        #expect(style.text.font.size == 20)
    }

    @Test func emKeepsAFractionalFontSize() throws {
        let style: ComputedStyle = try box("#x { font-size: 66%; width: 10em; }")
        let width: CGFloat = try #require(style.box.size.width)
        #expect(abs(width - 105.6) < 0.0001)
    }

    @Test func exIsTheFontsXHeight() throws {
        let style: ComputedStyle = try box("#x { font-size: 100px; width: 1ex; }")
        let font: BrowserFont = getFont(size: 100, weight: "normal", style: "roman", family: "serif")
        let width: CGFloat = try #require(style.box.size.width)
        #expect(abs(width - CTFontGetXHeight(font.ctFont)) < 0.0001)
    }

    @Test func chIsTheAdvanceOfZero() throws {
        let style: ComputedStyle = try box("#x { font-size: 100px; width: 1ch; }")
        let font: BrowserFont = getFont(size: 100, weight: "normal", style: "roman", family: "serif")
        let width: CGFloat = try #require(style.box.size.width)
        #expect(abs(width - font.measure("0")) < 0.0001)
    }

    @Test func negativeMarginInEx() throws {
        let style: ComputedStyle = try box("#x { width: 1ex; margin-right: -28ex; }")
        let ex: CGFloat = try #require(style.box.size.width)
        #expect(ex > 0)
        #expect(abs(style.box.spacing.margin.right + 28 * ex) < 0.0001)
    }

    @Test func unknownUnitsStayUnset() throws {
        let style: ComputedStyle = try box("#x { width: 2vmin; height: em; margin-left: 1.5lh; }")
        #expect(style.box.size.width == nil)
        #expect(style.box.size.height == nil)
        #expect(style.box.spacing.margin.left == 0)
    }

    @Test func emMarginFollowsAnInheritedFontSizeChangeOnResize() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="outer"><div id="x">text</div></div>"#,
            rules: """
                body { display: block; } div { display: block; }
                #outer { font-size: 10px; }
                @media (min-width: 600px) { #outer { font-size: 20px; } }
                #x { margin-left: 2em; }
                """
        )
        let x: ElementRef = try #require(page.firstElement(id: "x"))
        #expect(x.style.computed.box.spacing.margin.left == 40)

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        #expect(x.style.computed.text.font.size == 10)
        #expect(x.style.computed.box.spacing.margin.left == 20)
    }

    @Test func remFollowsTheRootFontSize() throws {
        let style: ComputedStyle = try box("""
            html { font-size: 10px; }
            #outer { font-size: 30px; }
            #x { width: 3rem; font-size: 2rem; }
            """)
        #expect(style.box.size.width == 30)
        #expect(style.text.font.size == 20)
    }

    @Test func remOnTheRootElement() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="x">text</div>"#,
            rules: "html { display: block; font-size: 2rem; width: 10rem; }"
        )
        let root: ElementRef = try #require(page.firstElement(tag: "html"))
        #expect(root.style.computed.text.font.size == 32)
        #expect(root.style.computed.box.size.width == 320)
    }

    @Test func remFollowsARootFontChangePastAFixedFontSize() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="outer"><div id="x">text</div></div>"#,
            rules: """
                body { display: block; } div { display: block; }
                html { font-size: 10px; }
                @media (min-width: 600px) { html { font-size: 20px; } }
                #outer { font-size: 12px; }
                #x { margin-left: 2rem; }
                """
        )
        let x: ElementRef = try #require(page.firstElement(id: "x"))
        #expect(x.style.computed.box.spacing.margin.left == 40)

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        #expect(x.style.computed.text.font.size == 12)
        #expect(x.style.computed.box.spacing.margin.left == 20)
    }
}

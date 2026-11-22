import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct IsSelectorTests {
    private let tailwind: String = #"""
        .bg-white{--tw-bg-opacity:1;background-color:rgb(255 255 255/var(--tw-bg-opacity,1))}
        .dark\:bg-neutral-950:is(.dark *){--tw-bg-opacity:1;background-color:rgb(10 10 10/var(--tw-bg-opacity,1))}
        """#

    private func render(_ html: String, _ css: String) -> LayoutTestPage {
        let page: LayoutTestPage = LayoutTestPage(html: html, rules: "")
        page.frame.setStyleRules(CSSParser(css).parse().rules)
        page.frame.setNeedsRender()
        page.frame.render()
        return page
    }

    private func background(_ page: LayoutTestPage, id: String) throws -> BrowserColor? {
        let element: ElementRef = try #require(page.firstElement(id: id))
        return element.ref.style.computed.visual.background.color
    }

    private func color(_ page: LayoutTestPage, id: String) throws -> BrowserColor {
        let element: ElementRef = try #require(page.firstElement(id: id))
        return element.ref.style.computed.text.color
    }

    @Test func darkVariantAppliesInsideTheDarkRoot() throws {
        let page: LayoutTestPage = render(
            #"<html class="dark"><body id="b" class="bg-white dark:bg-neutral-950"><p>x</p></body></html>"#,
            tailwind
        )
        #expect(try background(page, id: "b") == BrowserColor(red: 10 / 255, green: 10 / 255, blue: 10 / 255))
    }

    @Test func darkVariantStaysOffWithoutTheDarkRoot() throws {
        let page: LayoutTestPage = render(
            #"<html><body id="b" class="bg-white dark:bg-neutral-950"><p>x</p></body></html>"#,
            tailwind
        )
        #expect(try background(page, id: "b") == BrowserColor(red: 1, green: 1, blue: 1))
    }

    @Test func addingTheDarkClassLaterRestylesTheBody() throws {
        let page: LayoutTestPage = render(
            #"<html><body id="b" class="bg-white dark:bg-neutral-950"><p>x</p></body></html>"#,
            tailwind
        )
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        page.frame.js.run(script: "theme", code: "document.documentElement.classList.add('dark')")
        page.frame.render()
        #expect(try background(page, id: "b") == BrowserColor(red: 10 / 255, green: 10 / 255, blue: 10 / 255))
    }

    @Test func anySelectorInTheListCanMatch() throws {
        let page: LayoutTestPage = render(#"<h1 id="h">a</h1><p id="p">b</p><div id="d">c</div>"#, ":is(h1, p) { color: red }")
        #expect(try color(page, id: "h") == BrowserColor(red: 1, green: 0, blue: 0))
        #expect(try color(page, id: "p") == BrowserColor(red: 1, green: 0, blue: 0))
        #expect(try color(page, id: "d") == BrowserColor(red: 0, green: 0, blue: 0))
    }

    // Selectors 4 §15: :is() counts as its most specific argument, :where() counts as nothing.
    @Test func isKeepsSpecificityButWhereDropsIt() throws {
        let isPage: LayoutTestPage = render(#"<p id="x">a</p>"#, ":is(#x, p) { color: red } p { color: blue }")
        #expect(try color(isPage, id: "x") == BrowserColor(red: 1, green: 0, blue: 0))
        let whereLoses: LayoutTestPage = render(#"<p id="x" class="c">a</p>"#, ".c { color: blue } :where(#x) { color: red }")
        #expect(try color(whereLoses, id: "x") == BrowserColor(red: 0, green: 0, blue: 1))
    }

    @Test func unknownFunctionalPseudoClassDropsOnlyItsRule() throws {
        let page: LayoutTestPage = render(#"<p id="x">a</p>"#, ":nope(p) { color: red } p { color: blue }")
        #expect(try color(page, id: "x") == BrowserColor(red: 0, green: 0, blue: 1))
    }
}

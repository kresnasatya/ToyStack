import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct CascadeOriginTests {
    private func color(
        browser: String,
        author: String,
        html: String = #"<p id="x">text</p>"#
    ) throws -> BrowserColor {
        let page: LayoutTestPage = LayoutTestPage(html: html, rules: "")
        let rules: [RuleIndex.Rule] =
            CSSParser(browser, origin: .userAgent).parse().rules + CSSParser(author).parse().rules
        page.frame.setStyleRules(rules)
        page.frame.setNeedsRender()
        page.frame.render()
        let p: ElementRef = try #require(page.firstElement(id: "x"))
        return p.ref.style.computed.text.color
    }

    @Test func authorRuleBeatsMoreSpecificBrowserRule() throws {
        let result: BrowserColor = try color(browser: "#x { color: red; }", author: "p { color: blue; }")
        #expect(result == BrowserColor.parse("blue"))
    }

    @Test func importantBrowserRuleBeatsImportantAuthorRule() throws {
        let result: BrowserColor = try color(
            browser: "p { color: red !important; }",
            author: "#x { color: blue !important; }"
        )
        #expect(result == BrowserColor.parse("red"))
    }

    @Test func importantAuthorRuleBeatsNormalBrowserRule() throws {
        let result: BrowserColor = try color(
            browser: "#x { color: red; }",
            author: "p { color: blue !important; }"
        )
        #expect(result == BrowserColor.parse("blue"))
    }

    @Test func specificityStillDecidesWithinOneOrigin() throws {
        let result: BrowserColor = try color(
            browser: "",
            author: "#x { color: blue; } p { color: red; }"
        )
        #expect(result == BrowserColor.parse("blue"))
    }

    @Test func browserRuleAppliesWhenAuthorIsSilent() throws {
        let result: BrowserColor = try color(browser: "#x { color: red; }", author: "p { margin-top: 1px; }")
        #expect(result == BrowserColor.parse("red"))
    }
}

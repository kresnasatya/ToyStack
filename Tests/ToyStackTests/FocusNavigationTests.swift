import Testing

@testable import Engine

@Suite
@MainActor
struct FocusNavigationTests {
    @Test func tabOrderUsesExplicitTabIndex() {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"""
                <button id="second" tabindex="2">second</button>
                <button id="first" tabindex="1">first</button>
                """#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                button { display: inline; }
                """
        )

        #expect(page.tab.advanceTab())
        #expect(page.tab.focus?.attributes["id"] == "first")
        #expect(page.tab.advanceTab())
        #expect(page.tab.focus?.attributes["id"] == "second")
    }

    @Test func positiveTabIndexComesBeforeDocumentOrder() {
        let page: LayoutTestPage = Self.page(
            html: """
                <button id="plain">plain</button>
                <button id="zero" tabindex="0">zero</button>
                <button id="late" tabindex="2">late</button>
                <button id="early" tabindex="1">early</button>
                <button id="skipped" tabindex="-1">skipped</button>
            """
        )

        let order: [String?] = (0..<4).map { _ in
            page.tab.advanceTab()
            return page.tab.focus?.attributes["id"]
        }
        #expect(order == ["early", "late", "plain", "zero"])
        #expect(!page.tab.advanceTab())
    }

    @Test func equalPositiveTabIndexKeepsDocumentOrder() {
        let page: LayoutTestPage = Self.page(
            html: """
                <button id="a" tabindex="1">a</button>
                <button id="b" tabindex="1">b</button>
            """
        )

        #expect(page.tab.advanceTab())
        #expect(page.tab.focus?.attributes["id"] == "a")
        #expect(page.tab.advanceTab())
        #expect(page.tab.focus?.attributes["id"] == "b")
    }

    private static func page(html: String) -> LayoutTestPage {
        return LayoutTestPage(
            html: html,
            rules: """
                html { width: 600px; }
                body { display: block; }
                button { display: inline; }
            """
        )
    }
}
